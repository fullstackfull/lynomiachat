# Decimal amounts for order actions, written with as many decimals as an amount the store itself wrote (the order's
# total), so a refundable amount reads like the store's own figures and an agent's amount can be checked against it.
# Rounded down: a maximum is never shown above what the store allows.
module Commerce::Amount
  def self.format(value, like:)
    decimals = like.to_s.split('.', 2)[1].to_s.length
    integer, fraction = BigDecimal(value.to_s).round(decimals, BigDecimal::ROUND_DOWN).to_s('F').split('.')
    decimals.zero? ? integer : "#{integer}.#{fraction.to_s.ljust(decimals, '0')[0, decimals]}"
  end
end
