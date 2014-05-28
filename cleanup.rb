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

def clean_up(token, repository, results_repository, results_path)
  logger = Logger.new(STDOUT)

  client = Octokit::Client.new(:access_token=>token)

  # be sure to get files first and branches second so we don't race
  # to delete the results for a branch that doesn't yet exist
  files = client.contents(results_repository, :path=>results_path)

  # todo properly handle paginated results from github
  branches = client.branches(repository, :per_page => 100)
  pull_requests = client.pull_requests(repository, :state=>"open")

  files_for_deletion = []
  branches_deleted = Set.new
  file_branch = Hash.new

  files.each { |file| 
    if file.type == "file"
      logger.debug("Examining file #{file.sha} #{file.path}")
      file_content = Base64.decode64(client.blob(results_repository, file.sha).content)
      file_data = YAML.load(file_content)
      branch_name = file_data["branch_name"]

      if !branch_name.nil? && (file_data["pull_request_issue_id"].nil? || file_data["pull_request_issue_id"] == "")
        logger.debug("Examining branch #{branch_name} commit #{file_data["commit_sha"]}")

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
      end
    end
  }

  logger.info("#{files.size} files found. #{branches.size} active branches found. #{branches_deleted.size} deleted branches found (#{branches_deleted}). #{files_for_deletion.size} files queued for deletion")



  files_for_deletion.each { |file|
    logger.info("Deleting results file: #{file.path}. Source branch #{file_branch[file.path]} removed.")
    begin
      client.delete_contents(results_repository, file.path, "Source branch #{file_branch[file.path]} removed. Deleting results.", file.sha)
    rescue => e
      logger.error("Error deleting file: #{file.path} for branch #{file_branch[file.path]} message: #{e}")
    end
  }

  return true
end

