class Api::V1::Widget::Integrations::DyteController < Api::V1::Widget::BaseController
  before_action :set_message

  def add_participant_to_meeting
    if @message.content_type != 'integrations'
      return render json: {
        error: I18n.t('errors.dyte.invalid_message_type')
      }, status: :unprocessable_entity
    end

    response = dyte_processor_service.add_participant_to_meeting(
      @message.content_attributes['data']['meeting_id'],
      @conversation.contact,
      @message
    )
    render_response(response)
  end

  private

  def render_response(response)
    render json: response, status: response[:error].blank? ? :ok : :unprocessable_entity
  end

  def dyte_processor_service
    Integrations::Dyte::ProcessorService.new(account: @web_widget.inbox.account, conversation: @conversation)
  end

  # Scoped to the conversations the caller's own widget token authorises, not to the inbox. Looking a
  # message up across `@web_widget.inbox.messages` ignored the authenticated visitor entirely: any holder
  # of a widget token for this inbox -- and one is self-service, because `POST /api/v1/widget/config`
  # mints one from the public `website_token` -- could pass another visitor's `message_id` and receive a
  # RealtimeKit participant token for that visitor's meeting, issued under that visitor's identity.
  #
  # `conversations` is BaseController's existing scope and already handles the HMAC-verified case, so this
  # reuses the rule the rest of the widget API is held to rather than inventing a second one.
  def set_message
    @message = Message.where(conversation_id: conversations.select(:id)).find(permitted_params[:message_id])
    @conversation = @message.conversation
  end

  def permitted_params
    params.permit(:website_token, :message_id)
  end
end
