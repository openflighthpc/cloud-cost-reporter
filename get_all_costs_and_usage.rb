require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
require_relative './models/project_factory'

def all_projects(date, slack, rerun)
  ProjectFactory.new().all_projects_as_type.each do |project|
    project.record_instance_logs(rerun)
    project.get_cost_and_usage(date, slack, rerun)
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
end

date = Date.today - 2
slack = true
project = nil
rerun = false

ARGV.each do |arg|
  if %w[latest, all, slack].include?(arg)
    next
  elsif arg == "text"
    slack = false
  elsif arg == "rerun"
    rerun = true
  else
    valid = Date.parse(arg) rescue false
    if valid 
      date = valid
    elsif !project
      project = Project.find_by(name: arg)
    end
  end
end
    
if project
  project = ProjectFactory.new().as_type(project)
  project.record_instance_logs(rerun)
  project.get_cost_and_usage(date, slack, rerun)
else
  all_projects(date, slack, rerun)
end
