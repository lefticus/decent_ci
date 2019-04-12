# frozen_string_literal: true

require 'octokit'
require 'json'
require 'open3'
require 'pathname'
require 'active_support/core_ext/hash'
require 'find'
require 'logger'
require 'fileutils'
require 'ostruct'
require 'yaml'
require 'base64'

# Parsed test results for reporting back
class TestResult
  attr_reader :name
  attr_reader :failure_type

  def initialize(name, status, time, output, parsed_errors, failure_type)
    @name = name
    @status = status
    @time = time
    @output = output
    @parsed_errors = parsed_errors
    @failure_type = failure_type
  end

  def passed
    @status == 'passed' || @status == 'warning'
  end

  def warning
    @status == 'warning'
  end

  def inspect
    parsed_errors_array = []

    @parsed_errors&.each { |e| parsed_errors_array << e.inspect }

    {
      :name => @name,
      :status => @status,
      :time => @time,
      :output => @output,
      :parsed_errors => parsed_errors_array,
      :failure_type => @failure_type
    }
  end
end

# Captures a generic test message
class TestMessage
  attr_reader :name
  attr_reader :message

  def initialize(name, message)
    @name = name
    @message = message
  end

  def inspect
    { :name => @name, :message => @message }
  end
end
