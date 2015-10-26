#!/usr/bin/env ruby
# encoding: UTF-8 

require 'logger'
require_relative 'lib/build'
require_relative 'cleanup.rb'
require_relative 'lib/utility.rb'

require 'optparse'

$logger = Logger.new "decent_ci.log", 10
$created_dirs = []
$current_log_repository = nil
$current_log_deviceid = nil
$current_log_devicename = "#{Socket.gethostname}-#{Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address}"

remote_logger = nil


original_formatter = Logger::Formatter.new
$logger.formatter = proc { |severity, datetime, progname, msg|
  sev = nil
  case severity
  when "DEBUG"
    sev = Logger::DEBUG
  when "INFO"
    sev = Logger::INFO
  when "ERROR"
    sev = Logger::ERROR
  when "FATAL"
    sev = Logger::FATAL
  when "WARN"
    sev = Logger::WARN
  else
    sev = Logger::Unknown
  end

  msg = msg.gsub(/\/\/\S+@github/, "//<redacted>@github")

  if !$current_log_devicename.nil?
    msg = "[#{$current_log_devicename}] #{msg}"
  end

  if !$current_log_deviceid.nil?
    msg = "[#{$current_log_deviceid}] #{msg}"
  end

  if !$current_log_repository.nil?
    msg = "[#{$current_log_repository}] #{msg}"
  end

  if $remote_logger
    $remote_logger.add(sev, msg, progname)
  end

  res = original_formatter.call(severity, datetime, progname, msg.dump)
  puts res
  res
}

$logger.info "#{__FILE__} starting"
$logger.debug "#{__FILE__} starting, ARGV: #{ARGV}"
$logger.debug "Logging to decent_ci.log"


options = {}
options[:delay_after_run] = 300
options[:maximum_branch_age] = 30

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
    $logger.debug "aws-access-key-id: #{options[:aws_access_key_id]}"
  end

  opts.on("--aws-secret-access-key=[secret]") do |k|
    ENV["AWS_SECRET_ACCESS_KEY"] = k
    options[:aws_secret_access_key] = k
    $logger.debug "aws-secret-access-key: #{options[:aws_secret_access_key]}"
  end

  opts.on("--delay-after-run=N", Integer, "Time to delay after execution has completed, in seconds. Defaults to 300") do |k|
    options[:delay_after_run] = k
  end

  $logger.info "delay_after_run: #{options[:delay_after_run]}"

  opts.on("--maximum-branch-age=N", Integer, "Maximum age of a commit, in days, that will be built. Defaults to 30.") do |k|
    options[:maximum_branch_age] = k
  end

  $logger.info "maximum_branch_age : #{options[:maximum_branch_age]}"

  opts.on("--logentries-key=[secret]") do |k|
    if k != ""
      require 'le'
      $remote_logger = Le.new(k, :log_level => Logger::INFO)
      $logger.info "Initialized logentries.com remote logging"
    end
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

# keep this after the above environment dump so the key isn't included there
ENV["GITHUB_TOKEN"] = ARGV[1]

for conf in 2..ARGV.length-1
  $logger.info "Loading configuration #{ARGV[conf]}"
  $current_log_repository = ARGV[conf]

  begin
    # Loads the list of potential builds and their config files for the given
    # repository name
    b = Build.new(ARGV[1], ARGV[conf], options[:maximum_branch_age])
    test_mode = !(ARGV[0] =~ /false/i)

    $logger.info "Querying for updated branches"
    b.query_releases
    b.query_branches
    b.query_pull_requests

    did_daily_task = false

    b.results_repositories.each { |repo, results_repo, results_path|
      $logger.info "Checking daily task status for #{repo} #{results_repo} #{results_path}"

      if (test_mode || b.needs_daily_task(results_repo, results_path)) && ENV["DECENT_CI_SKIP_DAILY_TASKS"].nil? 
        did_daily_task = true

        count = 0
        succeeded = false
        while count < 5 && !succeeded do
          $logger.info "Executing clean_up task"
          begin
            clean_up(b.client, repo, results_repo, results_path, options[:maximum_branch_age])
            succeeded = true
          rescue => e
            $logger.error "Error running clean_up #{e} #{e.backtrace}"
          end
          count += 1
        end
      end
    }

    if did_daily_task
      b.get_pull_request_details.each { |d|

        $logger.debug "PullRequestDetail: #{d}"

        days = (DateTime.now() - DateTime.parse(d[:last_updated].to_s)).round()

        references = ""

        d[:notification_users].each { |u|
          references += "@#{u} "
        }

        message_to_post = "#{references}it has been #{days} days since this pull request was last updated."

        $logger.debug "Message: #{message_to_post}"

        if days >= d[:aging_pull_requests_numdays]
          if d[:aging_pull_requests_notification]
            $logger.info "Posting Message: #{message_to_post} to issue #{d[:id]}"
            if !test_mode
              b.client.add_comment(d[:repo], d[:id], message_to_post)
            else
              $logger.info "Not actually posting pull request, test mode"
            end
          else
            $logger.info "Not posting pull request age message, posting is disabled for this branch"
          end
        else
          $logger.info "Not posting pull request age message, only post every #{d[:aging_pull_requests_numdays]} days"
        end
      }
    end

    regression_baselines = []

    # loop over each potential build
    b.potential_builds.each { |p|

      if ENV["DECENT_CI_BRANCH_FILTER"].nil? || ENV["DECENT_CI_BRANCH_FILTER"] == '' || p.branch_name =~ /#{ENV["DECENT_CI_BRANCH_FILTER"]}/ || p.tag_name =~ /#{ENV["DECENT_CI_BRANCH_FILTER"]}/ || p.descriptive_string =~ /#{ENV["DECENT_CI_BRANCH_FILTER"]}/
        $logger.info "Looping over compilers"
        p.compilers.each { |compiler|
          $current_log_deviceid = p.device_id compiler

          if !(ENV["DECENT_CI_COMPILER_FILTER"].nil? || ENV["DECENT_CI_COMPILER_FILTER"] == '')
            compiler_string = p.device_id compiler
            if !(compiler_string =~ /#{ENV["DECENT_CI_COMPILER_FILTER"]}/)
              $logger.info "#{compiler_string} does not match filter of #{ENV["DECENT_CI_COMPILER_FILTER"]}, skipping this compiler build"
              next
            end
          end

          if compiler[:release_only] && !p.is_release
            $logger.info "#{p.device_id compiler} is a release_only configuration and #{p.descriptive_string} is not a release build, skipping"
            next
          end

          begin
            # reset potential build for the next build attempt
            p.next_build
            p.set_test_run test_mode

            if p.needs_run compiler
              $logger.info "Beginning build for #{compiler} #{p.descriptive_string}"
              p.post_results compiler, true
              begin
                regression_base = b.get_regression_base p

                if p.needs_regression_test(compiler) && regression_base
                  regression_base.set_test_run test_mode
                  p.clone_regression_repository compiler
                  regression_baselines << [compiler, regression_base];

                  if !File.directory?(regression_base.get_build_dir(compiler))
                    $logger.info "Beginning regression baseline (#{regression_base.descriptive_string}) build for #{compiler} #{p.descriptive_string}"
                    regression_base.do_build compiler, nil
                    regression_base.do_test compiler, nil
                  else
                    $logger.info "Skipping already completed regression baseline (#{regression_base.descriptive_string}) build for #{compiler} #{p.descriptive_string}"
                  end
                end

                p.do_package compiler, regression_base
                p.do_test compiler, regression_base
                p.do_coverage compiler, regression_base
                p.do_upload compiler, regression_base

                if p.needs_regression_test(compiler) && regression_base
                  p.do_regression_test compiler, regression_base
                  p.clean_up_regressions compiler
                end
              rescue => e
                $logger.error "Logging unhandled failure #{e} #{e.backtrace}"
                p.unhandled_failure "#{e}\n#{e.backtrace}"

                p.clean_up compiler
                p.clean_up_regressions compiler
              end

              if compiler[:collect_performance_results]
                p.collect_performance_results compiler
              end

              p.post_results compiler, false

              p.clean_up compiler
              p.clean_up_regressions compiler
            else
              $logger.info "Skipping build, already completed, for #{compiler} #{p.descriptive_string}"
            end
          rescue => e
            $logger.error "Error creating build: #{compiler} #{p.descriptive_string}: #{e} #{e.backtrace}"
            p.clean_up compiler
            p.clean_up_regressions compiler
          end

        }

      else
        $logger.info("Skipping build #{p.descriptive_string}, doesn't match environment filter #{ENV["DECENT_CI_BRANCH_FILTER"]}")
      end
    }

    regression_baselines.each{ |compiler, baseline| 
      begin
        $logger.info "Cleaning up regression_basline: #{baseline.descriptive_string} #{compiler}"
        baseline.clean_up compiler
      rescue => e
        $logger.error "Error cleaning up regression_baseline: #{baseline.descriptive_string} #{compiler} #{e} #{e.backtrace}"
      end
    }

  rescue => e
    $logger.fatal "Unable to initiate build system #{e} #{e.backtrace}"
  end

  $current_log_repository = nil
end

$logger.info "Execution completed, attempting to remove any left over files from the process"

$created_dirs.each{ |dir|
  try_hard_to_remove_dir dir
}

$logger.info "Execution completed, sleeping for #{options[:delay_after_run]}"
sleep(options[:delay_after_run])


