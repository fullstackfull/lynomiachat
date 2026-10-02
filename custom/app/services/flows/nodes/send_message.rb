# Send Message (docs/flow-builder/04-node-contracts.md §send message): one text message from the bot through Chatwoot's
# message path. Outside the channel's reply window nothing is sent: the conversation goes to humans.
class Flows::Nodes::SendMessage < Flows::Nodes::Base
  def enter
    return Flows::Step.finish(:handed_off, code: 'window_closed') unless @run.can_reply?

    @run.say(@data['text'])
    Flows::Step.next('next')
  end
end
