# Lynomia's listeners on Chatwoot's asynchronous events, after the Community and Enterprise ones.
module Custom::AsyncDispatcher
  def listeners
    super + [Commerce::RecoveryListener.instance]
  end
end
