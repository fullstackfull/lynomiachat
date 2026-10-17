# How a shopper says stop, and how they say yes again.
#
# AN OPT-OUT HAS TO BE POSSIBLE WITHOUT AN AGENT, or it is not an opt-out. A person who replies
# "STOP" to an automated message has refused; if that only works when somebody reads the
# conversation and clicks something, then whether their refusal takes effect depends on how
# busy the merchant is that afternoon. So the keywords are matched on the inbound message
# itself, the moment it arrives.
#
# STOP MEANS STOP, FOR BOTH CLASSES. It would be possible to read "STOP" as refusing marketing
# while order updates continue, and some regimes allow exactly that. This does not: a person
# typing STOP is asking not to be messaged, and answering "that only applied to some of our
# messages" is a reading that serves the merchant rather than the person. A shopper who wants
# only their parcel updates can say START again, which grants both.
#
# THE MATCH IS THE WHOLE MESSAGE, NOT A WORD INSIDE ONE. "Please stop sending me the wrong
# size" is a complaint for an agent, not an opt-out, and treating it as one silences a customer
# who was asking for help. So the message must be the keyword and nothing else, give or take
# punctuation and case.
#
# ARABIC IS NOT AN AFTERTHOUGHT HERE. This integration's shoppers write in Arabic, and an
# opt-out that only works in English is an opt-out most of them cannot use.
module Commerce::ConsentKeywords
  STOP = %w[stop unsubscribe cancel الغاء إلغاء ايقاف إيقاف توقف].freeze
  START = %w[start subscribe يبدأ ابدأ اشتراك موافق].freeze

  # Punctuation and whitespace only; the word itself is left alone, because Arabic letters are
  # not safe to "normalise" with anything less than a real library.
  TRIM = /\A[\s[[:punct:]]]+|[\s[[:punct:]]]+\z/

  def self.decision(content)
    word = content.to_s.strip.gsub(TRIM, '').downcase
    return if word.empty? || word.length > 20

    return :withdrawn if STOP.include?(word)

    :granted if START.include?(word)
  end
end
