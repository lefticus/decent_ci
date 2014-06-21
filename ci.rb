#!/usr/bin/env ruby
# encoding: UTF-8 

require 'logger'
require_relative 'lib/build'

require 'optparse'

$logger = Logger.new "decent_ci.log", 10

original_formatter = Logger::Formatter.new
$logger.formatter = proc { |severity, datetime, progname, msg|
  res = original_formatter.call(severity, datetime, progname, msg.dump)
  puts res
  res
}

$logger.info "#{__FILE__} starting, ARGV: #{ARGV}"
$logger.info "Logging to decent_ci.log"


options = {}
opts = OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options] <testruntrueorfalse> <githubtoken> <repositoryname> (<repositoryname> ...)"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end

  opts.on("-s", "--disable-ssl-verification", "Disable verification of ssl certificates") do |v|
    options[:disable_ssl_verification] = v
  end

  opts.on("--aws-access-key-id=[key]") do |k|
    ENV["AWS_ACCESS_KEY_ID"] = k
    options[:aws_access_key_id] = k
    $logger.info "aws-access-key-id: #{options[:aws_access_key_id]}"
  end

  opts.on("--aws-secret-access-key=[secret]") do |k|
    ENV["AWS_SECRET_ACCESS_KEY"] = k
    options[:aws_secret_access_key] = k
    $logger.info "aws-secret-access-key: #{options[:aws_secret_access_key]}"
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

opts.parse!


if ARGV.length < 3
  opts.abort(opts.to_s)
end

if options[:verbose]
  $logger.info "Changing log level to DEBUG"
  $logger.level = Logger::DEBUG
else
  $logger.info "Changing log level to INFO"
  $logger.level = Logger::INFO
end


if options[:disable_ssl_verification]
  $logger.warn "Disabling SSL certificate verification"
  require 'openssl'
  OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE # warning: already initialized constant VERIFY_PEER
end

envdump = ""
ENV.sort.each { |k,v|
  envdump += "#{k}=#{v}; "
}

$logger.info "Environment: #{envdump}"


for conf in 2..ARGV.length-1
  $logger.info "Loading configuration #{ARGV[conf]}"

  begin
    # Loads the list of potential builds and their config files for the given
    # repository name
    b = Build.new(ARGV[1], ARGV[conf])

    $logger.info "Querying for updated branches"
    b.query_releases
    b.query_branches
    b.query_pull_requests


    # loop over each potential build
    b.potential_builds.each { |p|

      if ENV["DECENT_CI_BRANCH_FILTER"].nil? || ENV["DECENT_CI_BRANCH_FILTER"] == '' || p.branch_name =~ /#{ENV["DECENT_CI_BRANCH_FILTER"]}/
        $logger.info "Looping over compilers"
        p.compilers.each { |compiler|

          begin
            # reset potential build for the next build attempt
            p.next_build
            p.set_test_run !(ARGV[0] =~ /false/i)

            if p.needs_run compiler
              $logger.info "Beginning build for #{compiler} #{p.descriptive_string}"
              p.post_results compiler, true
              begin
                regression_base = b.get_regression_base p
                if p.needs_regression_test compiler and regression_base
                  p.clone_regression_repository compiler

                  if !File.directory?(regression_base.get_build_dir(compiler))
                    $logger.info "Beginning regression basline (#{regression_base.descriptive_string}) build for #{compiler} #{p.descriptive_string}"
                    regression_base.do_build compiler, nil
                    regression_base.do_test compiler, nil
                  else
                    $logger.info "Skipping already completed regression basline (#{regression_base.descriptive_string}) build for #{compiler} #{p.descriptive_string}"
                  end
                end

                p.do_package compiler, regression_base
                p.do_test compiler, regression_base

                if regression_base
                  p.do_regression_test compiler, regression_base
                  p.clean_up_regressions compiler
                end
              rescue => e
                $logger.error "Logging unhandled failure #{e} #{e.backtrace}"
                p.unhandled_failure e
              end
              p.post_results compiler, false
              #            p.clean_up compiler
            else
              $logger.info "Skipping build, already completed, for #{compiler} #{p.descriptive_string}"
            end
          rescue => e
            $logger.error "Error creating build: #{compiler} #{p.descriptive_string}: #{e} #{e.backtrace}"
          end
        }

      else
        $logger.info("Skipping build #{p.descriptive_string}, doesn't match environment filter #{ENV["DECENT_CI_BRANCH_FILTER"]}")
      end
    }

  rescue => e
    $logger.fatal "Unable to initiate build system #{e} #{e.backtrace}"
  end
end


