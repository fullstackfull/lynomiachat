# What a customer's reply means to a Question node (docs/flow-builder/04-node-contracts.md §question): the accepted value,
# or nil. Fixed validators only, never a pattern supplied by a tenant. Arabic-Indic and Persian digits count as digits.
module Flows::Reply
  DIGITS = { '٠١٢٣٤٥٦٧٨٩' => '0123456789', '۰۱۲۳۴۵۶۷۸۹' => '0123456789' }.freeze
  NUMBER = /\A-?\d{1,15}([.,]\d{1,6})?\z/
  PHONE = /\A\+?\d{7,15}\z/

  PARSERS = { 'number' => :number, 'email' => :email, 'phone' => :phone, 'keywords' => :keyword }.freeze

  def self.parse(data, text)
    value = latin_digits(text.to_s.strip)
    return nil if value.empty? || value.length > Flows::Variables::MAX_VALUE

    parser = PARSERS[data['reply_type'] || 'any']
    parser ? send(parser, value, data) : value
  end

  def self.latin_digits(text) = DIGITS.reduce(text) { |result, (from, to)| result.tr(from, to) }

  def self.number(value, _data) = value.match?(NUMBER) ? value.tr(',', '.') : nil

  def self.email(value, _data) = value.match?(URI::MailTo::EMAIL_REGEXP) ? value.downcase : nil

  def self.phone(value, _data)
    digits = value.delete(' -().')
    digits.match?(PHONE) ? digits : nil
  end

  def self.keyword(value, data) = Array(data['keywords']).find { |word| word.to_s.strip.casecmp?(value) }

  private_class_method :number, :email, :phone, :keyword
end
