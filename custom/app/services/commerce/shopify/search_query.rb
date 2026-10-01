# The one place Shopify search strings (the `query` argument of `customers` and `orders`) are built. The string always
# travels as a GraphQL variable; this module keeps a value inside its filter under Shopify's search syntax
# (https://shopify.dev/docs/api/usage/search-syntax): text values are quoted as a phrase, which also makes the email
# filter exact, with backslash and double quote escaped, so no value can close the phrase or add a filter or operator.
# Ids are integers.
module Commerce::Shopify::SearchQuery
  def self.email(value) = phrase('email', value)

  def self.phone(value) = phrase('phone', value)

  def self.order_name(value) = phrase('name', value)

  def self.customer_id(value)
    id = Integer(value.to_s, 10)
    raise ArgumentError, 'customer id must be positive' unless id.positive?

    "customer_id:#{id}"
  end

  def self.phrase(field, value)
    %(#{field}:"#{value.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }}")
  end
  private_class_method :phrase
end
