require 'rubygems'
require 'rake'
dir = File.dirname(__FILE__)
$:.unshift("#{dir}/lib")
Rails.root = dir
require "acts_as_solr/tasks"
