#!/usr/bin/env ruby
# encoding: UTF-8 

require 'logger'
require_relative 'lib/build'


@logger = Logger.new(STDOUT)

if ARGV.length < 3
  puts "Usage: #{__FILE__} <testruntrueorfalse> <githubtoken> <repositoryname> (<repositoryname> ...)"
  abort("Not enough arguments")
end

@logger.info "Args: #{ARGV.length}"

for conf in 2..ARGV.length-1
  @logger.info "Loading configuration #{ARGV[conf]}"

  # Loads the list of potential builds and their config files for the given
  # repository name
  b = Build.new(ARGV[1], ARGV[conf])

  @logger.info "Querying for updated branches"
  b.query_releases
  b.query_branches
  b.query_pull_requests


  # loop over each potential build
  b.potential_builds.each { |p|
    
    if ENV["DECENT_CI_BRANCH_FILTER"].nil? || ENV["DECENT_CI_BRANCH_FILTER"] == '' || p.branch_name =~ /#{ENV["DECENT_CI_BRANCH_FILTER"]}/
      @logger.info "Looping over compilers"
      p.compilers.each { |compiler|

        begin
          # reset potential build for the next build attempt
          p.next_build
          p.set_test_run !(ARGV[0] =~ /false/i)

          if p.needs_run compiler
            @logger.info "Beginning build for #{compiler} #{p.descriptive_string}"
            p.post_results compiler, true
            begin
              p.do_package compiler
              p.do_test compiler
              p.do_install compiler

              if p.needs_regression_test compiler 
                r = b.get_regression_base p
                if r.needs_install compiler
                  r.do_build compiler
                  r.do_install compiler
                end
                p.do_regression_test compiler, r
              end
            rescue => e
              @logger.error "Logging unhandled failure #{e} #{e.backtrace}"
              p.unhandled_failure e
            end
            p.post_results compiler, false
            p.clean_up compiler
          else
            @logger.info "Skipping build, already completed, for #{compiler} #{p.descriptive_string}"
          end
        rescue => e
          @logger.error "Error creating build: #{compiler} #{p.descriptive_string}: #{e} #{e.backtrace}"
        end
      }

    else
      @logger.info("Skipping build #{p.descriptive_string}, doesn't match environment filter #{ENV["DECENT_CI_BRANCH_FILTER"]}")
    end
  }
end


