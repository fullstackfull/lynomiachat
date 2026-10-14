# Lynomia Flow Builder API (docs/flow-builder/02-architecture.md). A flow is one of the account's flow bots (AgentBot
# bot_type `flow`); this edits its versioned graph. A flow is connected to an inbox with Chatwoot's own
# POST /inboxes/:id/set_agent_bot. Managing flows takes the AgentBot permission to manage bots (AgentBotPolicy: account
# administrators), on `lynomia_flow_builder` accounts.
#
#   GET    /flows                   the account's flows
#   GET    /flows/channels          every inbox: whether it can run a flow, and which one it is running
#   GET    /flows/starters          ready-made graphs to start from, each one validated here
#   POST   /flows                   create: name, description
#   GET    /flows/:id               the flow, its draft graph (else the published one), validation errors, and
#                                  what a builder needs to edit it: the node catalogue, each node type's field
#                                  shapes, the variable allow-list and the templates it may send
#   PATCH  /flows/:id               name, description
#   POST   /flows/:id/duplicate    copy the flow and its graph into a new, unpublished flow
#   DELETE /flows/:id               delete (a flow that is not published and has no live session)
#   PUT    /flows/:id/draft         save the draft: graph, lock_version (409 when somebody else saved first)
#   POST   /flows/:id/publish       publish the draft (422 with the errors when it is not valid)
#   POST   /flows/:id/disable       stop starting sessions; live ones go to humans
#   GET    /flows/:id/sessions      the latest sessions (execution inspector): states and node ids, no message content
#   GET    /flows/:id/insights     how it is running: counts by outcome, and why runs stopped
#   POST   /flows/:id/simulate      Test Mode on the draft: inputs [{ text, reply_id } | { timer: true }]
class Api::V1::Accounts::FlowsController < Api::V1::Accounts::BaseController
  SESSIONS_LIMIT = 50
  INSIGHT_WINDOW = 30.days
  TEXT_MAX = 1024

  before_action :ensure_flow_builder_enabled
  before_action :fetch_flow, except: [:index, :create, :channels, :starters]
  before_action -> { authorize(@flow || AgentBot, :update?) }

  rescue_from Flows::Versions::Invalid do |error|
    render json: { errors: error.errors }, status: :unprocessable_entity
  end

  # SOMEBODY ELSE SAVED FIRST. 409 rather than 422, because the request was not malformed -- it was
  # built against a draft that has since moved. The current graph and lock_version travel with the
  # refusal so the editor can show what changed and let the person reapply, rather than making them
  # reload and lose what they were typing.
  rescue_from Flows::Versions::Stale do |error|
    render json: { error: 'flow_draft_stale', graph: error.current.graph, lock_version: error.current.lock_version,
                   updated_at: error.current.updated_at },
           status: :conflict
  end

  def index
    render json: { payload: flows.order(:name).map { |flow| flow_json(flow) } }
  end

  def show
    render json: show_json
  end

  # WHICH CHANNELS CAN RUN AN AUTOMATION, AND WHAT EACH ONE IS RUNNING.
  #
  # A flow is connected to an inbox with Chatwoot's own POST /inboxes/:id/set_agent_bot, which
  # neither says whether the inbox can run flows nor what is already attached -- and a client
  # that worked it out itself would be a second copy of Flows::ChannelCapabilities, drifting the
  # day a channel gains support. This is the question a "connect this flow" picker asks, answered
  # once, by the code that decides it.
  #
  # IT REPORTS, IT DOES NOT REFUSE, which is the same stance channel_eligibility takes and for the
  # same reason. Attaching a flow to an inbox that cannot run it is already harmless and already
  # caught: GraphValidator#check_channels refuses the PUBLISH with `unsupported_channel`, naming
  # the inbox, so nothing can go live on a channel that cannot run it. Forbidding the attachment
  # as well would duplicate that gate and make honest reporting unreachable -- and would mean a
  # flow attached before a channel gains support has to be re-attached afterwards rather than
  # simply starting to work.
  #
  # ONLY THE ACCOUNT'S OWN FLOW BOTS ARE NAMED. An inbox can carry any bot Chatwoot considers
  # accessible, which includes installation-wide ones with no account; those are an operator's
  # concern and a merchant has no business being shown or offered them, so an inbox running one
  # reports `flow: null` and `occupied_by_other: true` -- enough to warn that connecting would
  # replace something, without naming a bot from outside this account.
  def channels
    attached = flows.includes(:inboxes).flat_map { |flow| flow.inboxes.map { |inbox| [inbox.id, flow] } }.to_h
    inboxes = Current.account.inboxes.includes(:channel, :agent_bot).order(:name)

    render json: { payload: inboxes.map { |inbox| channel_json(inbox, attached[inbox.id]) } }
  end

  def channel_json(inbox, flow)
    { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type,
      runs_flows: Flows::ChannelCapabilities.for(inbox).present?,
      flow: flow && { id: flow.id, name: flow.name, state: lifecycle_of(flow) },
      occupied_by_other: flow.nil? && inbox.agent_bot.present? }
  end

  def create
    @flow = Current.account.agent_bots.create!(flow_params.merge(bot_type: :flow))
    Flows::Audit.record('flow.created', @flow, user: Current.user)
    render json: show_json, status: :created
  end

  def update
    @flow.update!(flow_params)
    render json: flow_json(@flow)
  end

  def destroy
    versions.delete!
    head :ok
  end

  # A COPY MADE ON THE SERVER, IN ONE TRANSACTION. The composition it replaces -- show, then
  # create, then save the draft -- is three round trips with no atomicity, and a failure between
  # the second and the third leaves behind an empty flow whose name says it is a copy of
  # something. It also counts against the flow ceiling at the same point every other create does,
  # because it goes through the same AgentBot validation.
  #
  # THE COPY IS ALWAYS A DRAFT, whatever the source was. A duplicate that published itself would
  # start sessions nobody asked for, on inboxes the copy is not attached to yet; the merchant
  # publishes it when they mean to. The source's inboxes are deliberately not copied either --
  # a flow and its copy on the same inbox is an ambiguity the merchant has to resolve, not one
  # this endpoint should guess at.
  def duplicate
    copy = nil

    ActiveRecord::Base.transaction do
      copy = Current.account.agent_bots.create!(name: duplicate_name, description: @flow.description, bot_type: :flow)
      Flows::Versions.new(copy, user: Current.user).save!(duplicate_graph, lock_version: 0)
      Flows::Audit.record('flow.duplicated', copy, user: Current.user, changes: { source_id: @flow.id, name: copy.name })
    end

    @flow = copy
    @versions = Flows::Versions.new(copy, user: Current.user)
    render json: show_json, status: :created
  end

  # `lock_version` is REQUIRED rather than optional-when-absent. An optional precondition is not a
  # precondition: any caller that omits it -- an old client, a script, anyone who noticed -- goes
  # back to silently overwriting the other editor, which is the defect. It is a parameter error,
  # not a conflict, when it is missing.
  def draft
    graph = params.require(:graph)
    versions.save!(graph.respond_to?(:to_unsafe_h) ? graph.to_unsafe_h : graph, lock_version: draft_lock_version)
    render json: show_json
  end

  def publish
    version = versions.publish!
    render json: flow_json(@flow).merge(published: version_json(version))
  end

  def disable
    versions.disable!
    render json: flow_json(@flow.reload)
  end

  # STARTING POINTS THE SERVER HAS CHECKED. A template is only worth offering if the graph it
  # produces will publish, and whether it will is this application's answer -- so the graphs live
  # here and a spec runs each one through the real validator. `available` says whether THIS
  # account may use it; an unavailable one is still listed, because a merchant told "this needs
  # Commerce" learns something and a merchant shown a shorter list learns nothing.
  def starters
    render json: { payload: Flows::Starters.for(Current.account) }
  end

  def sessions
    scope = @flow.flow_sessions.includes(:conversation, :flow_version).order(id: :desc).limit(SESSIONS_LIMIT)
    scope = scope.where(status: params[:status]) if FlowSession.statuses.key?(params[:status])
    render json: { payload: scope.map { |session| session_json(session) } }
  end

  # HOW THIS FLOW IS ACTUALLY RUNNING, counted rather than listed.
  #
  # `sessions` answers "what happened in the last fifty runs"; this answers "is it working" --
  # which is a different question and the one a merchant asks first. Counts by outcome, and the
  # failure codes behind the failed ones, over a window.
  #
  # NO MESSAGE CONTENT AND NO CUSTOMER, for the same reason `sessions` carries none: a summary of
  # how automation is behaving is an operational fact, and the moment it carries what somebody
  # wrote it becomes a second place conversation content can be read.
  def insights
    since = INSIGHT_WINDOW.ago
    scope = @flow.flow_sessions.where(created_at: since..)

    render json: {
      since: since, total: scope.count, live: scope.live.count,
      by_status: scope.group(:status).count,
      # Only the failed ones have a code; `end_reason` lives in context and is not grouped here
      # because grouping a jsonb key is a sequential scan over every session of the account.
      by_failure: scope.failed.where.not(failure_code: nil).group(:failure_code).count,
      versions: scope.joins(:flow_version).group('flow_versions.version').count
    }
  end

  def simulate
    render json: Flows::Simulator.new(@flow, versions.draft, simulation_inputs).call
  end

  private

  def ensure_flow_builder_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_flow_builder')
  end

  def flows = Current.account.agent_bots.flow

  def fetch_flow
    @flow = flows.find(params[:id])
  end

  def versions = @versions ||= Flows::Versions.new(@flow, user: Current.user)

  def flow_params = params.permit(:name, :description)

  # The client names the copy -- it is the one that knows the merchant's language. The fallback is
  # for a caller that does not, and is truncated because `name` has no length limit of its own and
  # a chain of duplicates would otherwise grow without bound.
  def duplicate_name
    params[:name].presence&.to_s&.strip.presence || "#{@flow.name} (copy)".first(255)
  end

  # The draft if there is one, else the published graph: what the merchant currently sees in the
  # editor. An archived version is history and is never what "duplicate this flow" means.
  def duplicate_graph
    (@flow.flow_versions.draft.first || @flow.published_flow_version)&.graph || Flows::Versions::STARTER
  end

  # JSON sends it as a number and a form sends it as a string, so it is normalised to a string
  # before parsing -- `Integer(0, 10)` raises, which is how this was found.
  def draft_lock_version
    value = params[:lock_version].to_s
    raise ActionController::ParameterMissing, :lock_version unless value.match?(/\A\d+\z/)

    Integer(value, 10)
  end

  def simulation_inputs
    inputs = params.require(:inputs)
    raise ActionController::ParameterMissing, :inputs unless inputs.is_a?(Array) && inputs.size <= Flows::Simulator::MAX_INPUTS

    inputs.map { |input| simulation_input(input) }
  end

  def simulation_input(input)
    input = input.permit(:text, :reply_id, :timer)
    return { timer: true } if input[:timer] == true

    text = input[:text]
    raise ActionController::ParameterMissing, :text unless text.is_a?(String) && text.strip.length.between?(1, TEXT_MAX)
    raise ActionController::ParameterMissing, :reply_id unless input[:reply_id].nil? || input[:reply_id].to_s.length <= 256

    { text: text, reply_id: input[:reply_id] }
  end

  def flow_json(flow)
    {
      id: flow.id, name: flow.name, description: flow.description,
      inboxes: flow.inboxes.map { |inbox| { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type } },
      published: version_json(flow.published_flow_version), draft: version_json(flow.flow_versions.draft.first),
      state: lifecycle_of(flow), live_sessions: flow.flow_sessions.live.count
    }
  end

  # WHICH OF THREE THINGS THIS FLOW IS, which `published` and `draft` cannot say between them.
  #
  # A flow that was published and then disabled has no published version and, until somebody edits
  # it, no draft either -- exactly like a flow created a minute ago and never touched. They are not
  # the same thing to a merchant: one was running and was turned off, with sessions and history
  # behind it, and the other has never done anything. A list that calls both of them "draft" is
  # telling the merchant the wrong thing about the one that matters.
  #
  # The archived check only runs for a flow that is in neither of the first two states, so it costs
  # nothing for a live or an in-progress flow.
  def lifecycle_of(flow)
    return 'published' if flow.published_flow_version
    return 'draft' if flow.flow_versions.draft.first
    return 'disabled' if flow.flow_versions.archived.exists?

    'draft'
  end

  def show_json
    current = @flow.flow_versions.draft.first || @flow.published_flow_version
    flow_json(@flow).merge(graph: current&.graph || Flows::Versions::STARTER,
                           errors: current ? versions.validate(current) : [], capabilities: Flows::ChannelCapabilities::WHATSAPP,
                           node_types: Flows::NodeTypes::TYPES, node_fields: Flows::NodeFields::FOR,
                           store_scopes: Flows::NodeFields::STORE_SCOPES, variables: Flows::Variables::SUGGESTED,
                           templates: sendable_templates, channel_eligibility: channel_eligibility)
  end

  # THE TEMPLATES A SEND TEMPLATE NODE IN THIS FLOW MAY ACTUALLY SEND, with the parameters each one takes.
  #
  # Served rather than derived by the builder, because the derivation is not simple and getting it wrong is
  # silent: which templates are sendable is Meta's approval plus the dashboard composer's own exclusions
  # (Flows::Template.sendable?), and which values one needs is parsed out of its components
  # (Flows::Template.slots). A builder that computed either itself would be a second implementation of a rule
  # that changes whenever Meta's component types do -- and the merchant would find out at publish.
  #
  # THE CANDIDATE INBOXES ARE THE VALIDATOR'S OWN -- literally its own method, not a copy of it -- so the set
  # offered here is the set that will be accepted at publish.
  def sendable_templates
    Flows::Template.sendable(Flows::TemplateValidator.candidates(Current.account, @flow.inboxes.to_a))
  end

  # WHAT THIS FLOW'S OWN INBOXES CAN ACTUALLY RUN, which is a different question from the one
  # `capabilities` answers.
  #
  # `capabilities` is the limit set the editor authors AGAINST -- how long a body may be, how many
  # buttons a list may hold -- and it stays WhatsApp's unconditionally on purpose: a flow is
  # written before it is connected to anything, and a new flow with no inbox still needs those
  # numbers to validate input against. Making it depend on the inboxes would leave every new flow
  # without them.
  #
  # This is the other half, and it is additive rather than a replacement: for each inbox the flow
  # is connected to, whether a flow can run there at all and which of the node types it uses that
  # inbox cannot do. It is what lets a client say "this action is unavailable, and here is why"
  # instead of offering something that will be refused at publish. The same answer the validator
  # already produces as `unsupported_channel`, read from the same place so the two cannot drift.
  def channel_eligibility
    types = Array(@flow.flow_versions.draft.first&.nodes || @flow.published_flow_version&.nodes).pluck('type').compact.uniq

    @flow.inboxes.map do |inbox|
      unsupported = Flows::ChannelCapabilities.unsupported(inbox, types)
      { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type,
        runs_flows: Flows::ChannelCapabilities.for(inbox).present?, unsupported_nodes: unsupported }
    end
  end

  def version_json(version)
    version&.slice(:id, :version, :status, :published_at, :updated_at, :lock_version)
  end

  def session_json(session)
    session.slice(:id, :status, :current_node_id, :steps_count, :failure_code, :created_at, :updated_at, :finished_at, :wake_at)
           .merge(end_reason: session.context['end_reason'], version: session.flow_version.version,
                  conversation_id: session.conversation.display_id)
  end
end
