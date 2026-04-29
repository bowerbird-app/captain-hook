# frozen_string_literal: true

require "active_support"
require "stringio"

module BootWarnings
  ACTIVE_SUPPORT_CONFIGURABLE_DEPRECATION = "ActiveSupport::Configurable is deprecated without replacement"

  def self.suppress_known_deprecations!
    deprecator = ActiveSupport.deprecator
    @original_behavior = Array(deprecator.behavior)

    deprecator.behavior = [lambda do |message, callstack, horizon, gem_name|
      next if message.include?(ACTIVE_SUPPORT_CONFIGURABLE_DEPRECATION)

      @original_behavior.each do |handler|
        if handler.is_a?(Symbol)
          deprecator.public_send(handler, message, callstack, horizon, gem_name)
        else
          handler.call(message, callstack, horizon, gem_name)
        end
      end
    end]
  end

  def self.restore_deprecations!
    return unless @original_behavior

    ActiveSupport.deprecator.behavior = @original_behavior
  end

  def self.with_filtered_stderr
    original_stderr = $stderr
    captured_stderr = StringIO.new
    $stderr = captured_stderr
    yield
  ensure
    $stderr = original_stderr
    original_stderr.write(filter_known_boot_warnings(captured_stderr.string))
  end

  def self.filter_known_boot_warnings(output)
    filtered_lines = []
    lines = output.lines
    index = 0

    while index < lines.length
      if lines[index].include?(ACTIVE_SUPPORT_CONFIGURABLE_DEPRECATION)
        index += 1
        index += 1 while index < lines.length && !lines[index].start_with?(" (called from")
        index += 1 if index < lines.length
      else
        filtered_lines << lines[index]
        index += 1
      end
    end

    filtered_lines.join
  end
end
