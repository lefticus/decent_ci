[![Code Climate](https://codeclimate.com/github/lefticus/decent_ci/badges/gpa.svg)](https://codeclimate.com/github/lefticus/decent_ci)
[![Test Coverage](https://codeclimate.com/github/lefticus/decent_ci/badges/coverage.svg)](https://codeclimate.com/github/lefticus/decent_ci)
[![status](https://sourcegraph.com/api/repos/github.com/lefticus/decent_ci/.badges/status.png)](https://sourcegraph.com/github.com/lefticus/decent_ci)
[![docs examples](https://sourcegraph.com/api/repos/github.com/lefticus/decent_ci/.badges/docs-examples.png)](https://sourcegraph.com/github.com/lefticus/decent_ci)
[![Build Status](https://travis-ci.org/lefticus/decent_ci.svg)](https://travis-ci.org/lefticus/decent_ci)

(Note: for NREL specific notes, see here: https://github.com/lefticus/decent_ci/wiki/Decent-CI-Cheat-Sheet)

decent_ci
=========

Decent CI is a decentralized continuous integration system for cmake based projects designed for use with github.

It queries a given repository for a the set of branches, releases and pull request. The project is written in ruby and requires:

- ruby
  - octokit gem
  - activesupport gem
- git

To configure your application for use with Decent CI, you need put approriate `.decent_ci*.yml` files in the root of your project. Only branches / tags which contain the required files will be tested.

Examples can be found in the [confs](confs) folder.

Decent CI is tested on Windows, Linux and MacOS.

# Windows Installation / Usage

 1. Install git bash http://git-scm.com/download/win
 2. Install python https://www.python.org/downloads/ add it to the path (needed for energyplus regressions)
 3. Install ruby 2.0+ http://rubyinstaller.org/downloads/ add it to the path
 4. Install cmake http://www.cmake.org/cmake/resources/software.html add it to the path
 5. Install mingw fortran if desired (for EnergyPlus) add it to the path
 6. Download the updated windows ssl certificate file and add `SSL_CERT_FILE` environment variable pointing to it. See here: https://gist.github.com/fnichol/867550
 7. `gem install octokit activesupport`
 8. Get gist from here https://gist.github.com/lefticus/10914850
 9. Create github token for the user
 10. Launch git bash, execute `ruby ./run_ci.rb <build_folder> <true/false test mode> <token> <respository>`

# MacOS Installation / Usage

 1. Install ruby gems octokit and activesupport. You will need to follow these instructions http://stackoverflow.com/questions/22352838/ruby-gem-install-json-fails-on-mavericks-and-xcode-5-1-unknown-argument-mul
 2. `sudo gem install octokit activesupport`
 3. Get gist from here https://gist.github.com/lefticus/10914850
 4. Create github token for the user
 5. Execute `ruby ./run_ci.rb <build_folder> <true/false test mode> <token> <respository>`

# Linux Installation / Usage

 1. `sudo apt-get install cmake git g++ ruby irb python gfortran cppcheck` Make sure ruby installed is 1.9+
 2. `sudo gem install octokit activesupport`
 3. Get gist from here https://gist.github.com/lefticus/10914850
 4. Create github token for the user
 5. Execute `ruby ./run_ci.rb <build_folder> <true/false test mode> <token> <respository>`




