require 'aws-sdk-core'
require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
load './models/ProjectFactory.rb'

ENV["REGION"]="us-east-1"
Aws.config.update({region: ENV["REGION"]})

ProjectFactory.new().all_projects_as_type.each do |project|
  #project.get_some_pricing
  project.get_cost_and_usage
  #project.get_forecasts
  #project.get_instance_usage_data("i-062dd1030e63f9cff")
  #project.get_instance_cpu_utlization("i-0b2c0cb3524d62615")
  project.record_instance_logs
end
