# encoding: UTF-8 

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

def clean_up(client, repository, results_repository, results_path)
  if $logger.nil?
    logger = Logger.new(STDOUT)
  else
    logger = $logger
  end

  # client = Octokit::Client.new(:access_token=>token)

  # be sure to get files first and branches second so we don't race
  # to delete the results for a branch that doesn't yet exist
  files = github_query(client) { client.contents(results_repository, :path=>results_path) }

  branch_history_limit = 10
  file_age_limit = 9000
  if files.size > 800
    branch_history_limit = 5
    file_age_limit = 60
    logger.info("Hitting directory size limit #{files.size}, reducing history to #{branch_history_limit} data points")
  end

  # todo properly handle paginated results from github
  branches = github_query(client) { client.branches(repository, :per_page => 200) }
  releases = github_query(client) { client.releases(repository, :per_page => 200) }
  pull_requests = github_query(client) { client.pull_requests(repository, :state=>"open") }

  files_for_deletion = []
  branches_deleted = Set.new
  file_branch = Hash.new
  branch_files = Hash.new

  releases.each { |release|
    logger.debug("Loaded release: '#{release.tag_name}'")
  }

  files.each { |file| 
    if file.type == "file"
      logger.debug("Examining file #{file.sha} #{file.path}")
      file_content = Base64.decode64(github_query(client) { client.blob(results_repository, file.sha).content })
#      file_content = Base64.decode64(github_query(client) { client.contents(results_repository, :path=>file.path) })
      file_data = YAML.load(file_content)
      branch_name = file_data["branch_name"]

      days_old = (DateTime.now - file_data["date"].to_datetime).to_f
      if (days_old > file_age_limit) 
        logger.debug("Results file has been around for #{days_old} days. Deleting.")
        files_for_deletion << file
      end

      if file.path =~ /DailyTaskRun$/
        logger.debug("DailyTaskRun created on: #{file_data["date"]}")
        days_since_run = (DateTime.now - file_data["date"].to_datetime).to_f
        if days_since_run > 5
          logger.debug("Deleting old DailyTaskRun file #{file.path}")
          files_for_deletion << file
        end

      elsif !file_data["pending"]
        if !branch_name.nil? && (file_data["pull_request_issue_id"].nil? || file_data["pull_request_issue_id"] == "")
          logger.debug("Examining branch #{branch_name} commit #{file_data["commit_sha"]}")

          file_key = {:device_id => file_data["device_id"], :branch_name => branch_name}
          file_data = {:date => file_data["date"], :file => file}

          if branch_files[file_key].nil?
            branch_files[file_key] = []
          end
          branch_files[file_key] << file_data


          branch_found = false
          branches.each{ |b|
            if b.name == branch_name
              branch_found = true
              break
            end
          }

          if !branch_found
            logger.debug("Branch not found, queuing results file for deletion: #{file_data["title"]}")
            files_for_deletion << file
            file_branch[file.path] = branch_name
            branches_deleted << branch_name
          end
        elsif !file_data["tag_name"].nil?
          tag_found = false
          days_after = nil
          releases.each{ |r|
            if r.tag_name == file_data["tag_name"]
              tag_found = true
              days_after = (file_data["date"].to_datetime - DateTime.parse(r.published_at.to_s)).to_f
              if (days_after < -1)
                logger.debug(" release is newer than results? (#{DateTime.parse(r.published_at.to_s)} vs #{file_data["date"].to_datetime})")
              end
              break
            end
          }

          if !tag_found
            logger.debug("Release not found, queuing results for deletion: #{file_data["title"]}, tag: '#{file_data["tag_name"]}'")
            files_for_deletion << file
          else
            logger.debug("Release results created #{days_after} days  after tag was created");
            if days_after < -1
              logger.debug("Release created AFTER results, queuing results for deletion: #{file_data["title"]}")
              files_for_deletion << file
            end
          end
        end

      else 
        # is pending
        logger.debug("Pending build was created on: #{file_data["date"]}")
        days_pending = (DateTime.now - file_data["date"].to_datetime).to_f
        if (days_pending > 1) 
          logger.debug("Build has been pending for > 1 day, deleting pending file to try again: #{file_data["title"]}")
          files_for_deletion << file
        end

      end

    end
  }

  logger.info("#{files.size} files found. #{branches.size} active branches found. #{branches_deleted.size} deleted branches found (#{branches_deleted}). #{files_for_deletion.size} files queued for deletion")

  branch_files.each { |key, filedata|
    logger.info("Examining branch data: #{key}")
    filedata.sort_by! { |i| i[:date] }

    # allow at most branch_history_limit results for each device_id / branchname combination. The newest, specifically
    if filedata.size() > branch_history_limit
      filedata[0..filedata.size() - (branch_history_limit + 1)].each { |file|
        logger.debug("Marking old branch results file for deletion #{file[:file].path}")
        files_for_deletion << file[:file]
      }
    end
  }


  files_for_deletion.each { |file|
    logger.info("Deleting results file: #{file.path}. Source branch #{file_branch[file.path]} removed, or file too old")
    begin
      github_query(client) { client.delete_contents(results_repository, file.path, "Source branch #{file_branch[file.path]} removed. Deleting results.", file.sha) }
    rescue => e
      logger.error("Error deleting file: #{file.path} for branch #{file_branch[file.path]} message: #{e}")
    end
  }

  return true
end

