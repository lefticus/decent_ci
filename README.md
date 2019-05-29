decent_ci
=========

[![Build Status](https://travis-ci.org/Myoldmopar/decent_ci.svg?branch=master)](https://travis-ci.org/Myoldmopar/decent_ci)
[![Coverage Status](https://coveralls.io/repos/github/Myoldmopar/decent_ci/badge.svg?branch=master)](https://coveralls.io/github/Myoldmopar/decent_ci?branch=master)
[![Maintainability](https://api.codeclimate.com/v1/badges/2ec29367c38e431d4b8a/maintainability)](https://codeclimate.com/github/Myoldmopar/decent_ci/maintainability)

Forked from https://github.com/lefticus/decent_ci, tailored to [EnergyPlus ](https://github.com/NREL/EnergyPlus) specific needs.  If you are using this fork of it for anything other than EnergyPlus, please be aware we are not guaranteeing anything stable here.

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

TO BE UPDATED

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

TO BE UPDATED 

 1. Install ruby gems octokit and activesupport. You will need to follow these instructions http://stackoverflow.com/questions/22352838/ruby-gem-install-json-fails-on-mavericks-and-xcode-5-1-unknown-argument-mul
 2. `sudo gem install octokit activesupport`
 3. Get gist from here https://gist.github.com/lefticus/10914850
 4. Create github token for the user
 5. Execute `ruby ./run_ci.rb <build_folder> <true/false test mode> <token> <respository>`

# Linux Installation / Usage

```
sudo apt-get install git cmake g++ gfortran cmake-curses-gui curl ccache python-pip texlive-full valgrind lcov gcovr clang-format cppcheck
pip install boto beautifulsoup4 soupsieve
sudo gem install activesupport octokit
cd ~
mkdir ~/ci
git clone https://gist.github.com/c51580a92556ef344216c22ec390aa31.git ci_script
cd ci_script
ruby run_ci.rb ~/ci <AWS_STUFF> <true/false test mode> <GH_TOKEN> NREL/EnergyPlus
```

# Documentation

Documentation is currently stubbed out, and needs to be fully fleshed out.
In any case, the docs are built using Yard.
To get started, `gem install yard` or bundle it from the doc section of the Gemfile.
Then from the root of the repo, just run `yardoc`, and it will scan the lib directory, generating html docs and dropping them into the `docs/` folder.
GitHub then hosts the documentation on the GitHub page: https://myoldmopar.github.io/decent_ci/ 
