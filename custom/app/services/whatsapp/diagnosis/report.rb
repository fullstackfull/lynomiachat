# frozen_string_literal: true

# The report a Lynomia WhatsApp diagnosis builds: the lines, the pass/fail/blocked checks, and the masking rules
# every line goes through. Kept apart from the checks themselves so there is exactly one place that decides how a
# secret or a customer's phone number is allowed to appear in output that gets pasted into an issue.
class Whatsapp::Diagnosis::Report
  PASS = 'PASS'
  FAIL = 'FAIL'
  BLOCKED = 'BLOCKED'

  attr_reader :checks

  def initialize(&emit)
    @emit = emit
    @lines = []
    @checks = []
  end

  def say(line)
    @lines << line
    @emit&.call(line)
  end

  def heading(text)
    say ''
    say '=' * 100
    say text
    say '=' * 100
  end

  def check(name, passed, detail, note: nil)
    state = passed ? PASS : FAIL
    @checks << { name: name, state: state, detail: detail, note: note }
    say format('  [%<state>s] %<name>s — %<detail>s', state: state, name: name, detail: detail)
    say "         #{note}" if !passed && note.present?
  end

  def blocked(name, reason)
    @checks << { name: name, state: BLOCKED, detail: reason, note: nil }
    say "  [#{BLOCKED}] #{name} — #{reason}"
  end

  # One read-only call AND the reporting of what it returned, both inside the rescue. A failure is recorded as
  # BLOCKED rather than raised, so neither an unavailable endpoint nor a response in an unexpected shape costs the
  # rest of the report. Callers therefore interpret the response inside this block, not after it.
  def read(label)
    say "#{label}:"
    yield
  rescue StandardError => e
    blocked(label, "#{e.class.name}: #{e.message.to_s[0, 200]}")
    nil
  end

  def rows(pairs, indent: '')
    pairs.each { |label, value| say "#{indent}#{label}: #{value}" }
  end

  def summarise
    heading('SUMMARY')
    checks.each { |entry| summary_line(entry) }
    say ''
    say "#{count(PASS)} passed, #{count(FAIL)} failed, #{count(BLOCKED)} blocked"
    fix_order
  end

  def to_s = @lines.join("\n")

  def mask(value)
    return '<blank>' if value.blank?

    "#{value.to_s[0, 4]}…#{value.to_s[-2, 2]} (#{value.to_s.length} chars)"
  end

  # A real customer's number must not end up in a report that gets shared.
  def mask_phone(value)
    return '<blank>' if value.blank?

    "#{value.to_s[0, 5]}•••#{value.to_s[-2, 2]}"
  end

  def format_unix(value)
    return '<none>' if value.blank? || value.to_i.zero?

    Time.zone.at(value.to_i).iso8601
  end

  private

  def count(state) = checks.count { |entry| entry[:state] == state }

  def summary_line(entry)
    say format('%<state>-7s %<name>s — %<detail>s', state: entry[:state], name: entry[:name], detail: entry[:detail])
    say "        #{entry[:note]}" if entry[:state] == FAIL && entry[:note].present?
  end

  def fix_order
    failures = checks.select { |entry| entry[:state] == FAIL }
    return if failures.empty?

    heading('WHAT TO FIX, IN ORDER')
    failures.each_with_index { |entry, index| say "#{index + 1}. #{entry[:name]} — #{entry[:detail]}" }
    say ''
    say 'Fix the highest one first and re-run this task. Do not change Meta configuration for any check that passed.'
  end
end
