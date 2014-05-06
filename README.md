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

To use on Windows you will need to install the official ruby 2.x and git sh packages.

You may need to follow these directions to deal with an ssl certificate error on Windows: https://gist.github.com/fnichol/867550

To install the required gems on MacOS you may need to follow these instructions http://stackoverflow.com/questions/22352838/ruby-gem-install-json-fails-on-mavericks-and-xcode-5-1-unknown-argument-mul

A utility script, run_ci.rb, has been written to run the decent_ci scripts continuously in a loop:

https://gist.github.com/lefticus/10914850



