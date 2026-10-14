# Lynomia Flow Builder API (docs/flow-builder/02-architecture.md). A flow is one of the account's flow bots (AgentBot
# bot_type `flow`); this edits its versioned graph. A flow is connected to an inbox with Chatwoot's own
# POST /inboxes/:id/set_agent_bot. Managing flows takes the AgentBot permission to manage bots (AgentBotPolicy: account
# administrators), on `lynomia_flow_builder` accounts.
#
#   GET    /flows                   the account's flows
#   POST   /flows                   create: name, description
#   GET    /flows/:id               the flow, its draft graph (else the published one), validation errors
#   PATCH  /flows/:id               name, description
#   DELETE /flows/:id               delete (a flow that is not published and has no live session)
#   PUT    /flows/:id/draft         save the draft: graph, lock_version (409 when somebody else saved first)
#   POST   /flows/:id/publish       publish the draft (422 with the errors when it is not valid)
#   POST   /flows/:id/disable       stop starting sessions; live ones go to humans
#   GET    /flows/:id/sessions      the latest sessions (execution inspector): states and node ids, no message content
#   POST   /flows/:id/simulate      Test Mode on the draft: inputs [{ text, reply_id } | { timer: true }]
class Api::V1::Accounts::FlowsController < Api::V1::Accounts::BaseController
  SESSIONS_LIMIT = 50
  TEXT_MAX = 1024

  before_action :ensure_flow_builder_enabled
  before_action :fetch_flow, except: [:index, :create]
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

  def sessions
    scope = @flow.flow_sessions.includes(:conversation, :flow_version).order(id: :desc).limit(SESSIONS_LIMIT)
    scope = scope.where(status: params[:status]) if FlowSession.statuses.key?(params[:status])
    render json: { payload: scope.map { |session| session_json(session) } }
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
      live_sessions: flow.flow_sessions.live.count
    }
  end

  def show_json
    current = @flow.flow_versions.draft.first || @flow.published_flow_version
    flow_json(@flow).merge(graph: current&.graph || Flows::Versions::STARTER,
                           errors: current ? versions.validate(current) : [], capabilities: Flows::ChannelCapabilities::WHATSAPP,
                           node_types: Flows::NodeTypes::TYPES, variables: Flows::Variables::SUGGESTED)
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
