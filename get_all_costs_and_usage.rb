require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
load './models/ProjectFactory.rb'

ProjectFactory.new().all_projects_as_type.each do |project|
  project.get_cost_and_usage
  project.record_instance_logs
  if ARGV.include?("forecasts")
    project.get_forecasts
  end
  #project.each_instance_usage_data
  #project.get_instance_usage_data("i-062dd1030e63f9cff")
  #project.get_instance_cpu_utilization("i-0b2c0cb3524d62615")
  #project.get_data_out
  #project.get_ssd_usage
  #puts project.get_cost_per_hour('r5.2xlarge')
end
