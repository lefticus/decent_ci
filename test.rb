require 'octokit'
require 'json'
require 'open3'
require 'pathname'
require 'active_support/core_ext/hash'
require 'find'

class Configuration
  def initialize(token, results_repository, results_path, repository, compiler, compiler_version, architecture, os)
    @token = token
    @results_repository = results_repository
    @results_path = results_path
    @repository = repository
  end

  def token
    @token
  end

  def repository
    @repository
  end

  def repository_name=(name)
    @repository_name = name
  end

  def repository_name
    @repository_name
  end


end

class PotentialBuild

  def initialize(client, config, repository, tag_name, commit_sha, branch_name, is_release, release_assets)
    @config = config
    @repository = repository
    @tag_name = tag_name
    @commit_sha = commit_sha
    @branch_name = branch_name
    @is_release = is_release
    @release_assets = release_assets

    @buildid = @tag_name ? @tag_name : @commit_sha
    @refspec = @tag_name ? @tag_name : @branch_name

    @has_release_package = false

    if is_release
      if release_assets
        release_assets.each { |asset|
          if asset.name = packageName()
            @has_release_package = true
          end
        }
      end
    end
  end

  def buildBaseName
    "#{@config.repository_name}-#{RUBY_PLATFORM}-#{@buildid}"
  end

  def packageName
    "#{buildBaseName()}.deb"
  end

  def processGccResults(stdout, stderr, result)
    puts "Error " + stderr
    stderr.split("\n").each { |err|
      puts "Checking line: #{err}"

      /(?<filename>\S+):(?<linenumber>[0-9]+):(?<colnumber>[0-9]+): (?<messagetype>\S+): (?<message>.*)/ =~ err

      if !filename.nil?
        puts Pathname.new(filename).realpath.relative_path_from(Pathname.new(buildBaseName).realdirpath)
      end
    }

    return result
  end

  def checkout(src_dir)
    output = `mkdir #{src_dir}; cd #{src_dir} && rm -rf * && git init && git pull https://#{@config.token}@github.com/#{@repository} #{@refspec}`
    if !@sha.nil? && !@sha == ""
      output = `cd #{src_dir} && git checkout #{@sha}`
    end
  end

  def build(src_dir, build_dir, build_type)
    out, err, result = Open3.capture3("mkdir -p #{build_dir} && cd #{build_dir} && cmake ../ -DCMAKE_BUILD_TYPE:STRING=#{build_type} && make -j3")
    if processGccResults(out,err,result)

    end
  end

  def package(build_dir)
    pack_stdout, pack_stderr, pack_result = Open3.capture3("cd #{build_dir} && cpack -G DEB -p #{packageName}")

    if pack_result != 0
      raise "Error building package: #{pack_stderr}"
    end

    return "#{build_dir}/#{packageName}"
  end

  def doPackage
    if @is_release && !@has_release_package
      src_dir = "#{buildBaseName}-release"
      build_dir = "#{src_dir}/build"

      checkout src_dir
      build src_dir, build_dir, "Release"
      begin 
        built_package = package build_dir
      rescue => e
        puts "Error creating package #{e}"
      end

      puts "Package successfully built at: #{built_package}"
    end
  end

  def processCTestResults build_dir, stdout, stderr, result
    Find.find(build_dir) do |path|
      if path =~ /.*Test.xml/
        results = Hash.from_xml(File.open(path).read)
        puts results["Site"]["Testing"]
      end
    end
  end


  def test build_dir
    test_stdout, test_stderr, test_result = Open3.capture3("cd #{build_dir} && ctest -D ExperimentalTest");
    processCTestResults build_dir, test_stdout, test_stderr, test_result
  end

  def doTest
    src_dir = buildBaseName
    build_dir = "#{buildBaseName}/build"

    checkout src_dir
    build src_dir, build_dir, "Debug"
    test build_dir

  end 



  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

end

class Build
  def initialize(config)
    @config = config
    @client = Octokit::Client.new(:access_token=>config.token)
    @user = @client.user
    @user.login
    @potentialBuilds = []

    @config.repository_name = @client.repo(@config.repository).name
  end

  def queryReleases
    releases = @client.releases(@config.repository)

    releases.each { |r| 
      @potentialBuilds << PotentialBuild.new(@client, @config, @config.repository, r.tag_name, nil, nil, true, r.assets)
    }
  end

  def queryBranches
    branches = @client.branches(@config.repository)

    branches.each { |b| 
      @potentialBuilds << PotentialBuild.new(@client, @config, @config.repository, nil, b.commit.sha, b.name, false, nil)
    }
  end

  def queryPullRequests
    pullRequests = @client.pull_requests(@config.repository, :state=>"open")

    pullRequests.each { |p| 
      @potentialBuilds << PotentialBuild.new(@client, @config, p.head.repo.full_name, nil, p.head.sha, nil, false, nil)
    }
  end

  def potentialBuilds
    @potentialBuilds
  end
end

b = Build.new(Configuration.new("d2a821665446e86f90b15fc57d50d7a5a202247f", "ChaiScript/chaiscript-build-results", "_posts", "lefticus/cpp_project_with_errors", "gcc", "4.8.1", "x86_64", "ubuntu"))
b.queryReleases
b.queryBranches
b.queryPullRequests

b.potentialBuilds.each { |p| puts p.inspect }

b.potentialBuilds.each { |p| 
  p.doPackage 
  p.doTest
}


#response = client.create_contents("ChaiScript/chaiscript.github.io",
#                                   "test_create.txt",
#                                   "I am commit-ing",
#                                   "Here be the content\n")
#
#puts response
