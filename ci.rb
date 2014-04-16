# encoding: UTF-8 

require 'logger'
require_relative 'lib/build'


@logger = Logger.new(STDOUT)


@logger.info "Args: #{ARGV.length}"

for conf in 1..ARGV.length-1
  @logger.info "Loading configuration #{ARGV[conf]}"
  b = Build.new(ARGV[0], ARGV[conf])

  @logger.info "Querying for updated branches"
  b.query_releases
  b.query_branches
  b.query_pull_requests


  b.potential_builds.each { |p|

    @logger.info "Looping over compilers"
    p.compilers.each { |compiler|

      begin
        # reset potential build for the next build attempt
        p.next_build
        p.set_test_run true

        if p.needs_run compiler
          @logger.info "Beginning build for #{compiler} #{p.descriptive_string}"
          p.post_results compiler, true
          begin 
            p.do_package compiler
            p.do_test compiler
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
  }
end

