require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
require_relative './models/project_factory'

def all_projects(date, slack)
  ProjectFactory.new().all_projects_as_type.each do |project|
    project.record_instance_logs
    project.get_cost_and_usage(date, slack)
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

if ARGV[1] && ARGV[1] != "latest"
  valid = Date.parse(ARGV[1]) rescue false
  if !valid
    puts "Provided date invalid"
    return
  end
  date = valid
end

slack = true
if ARGV[2] && ARGV[2] == "text"
  slack = false
end

if ARGV[0] && ARGV[0] != "all"  
  project = Project.find_by(name: ARGV[0])
  if project == nil
    puts "Project with that name not found"
    return
  end
  project = ProjectFactory.new().as_type(project)
  project.get_cost_and_usage(date, slack)
  project.record_instance_logs
else
  all_projects(date, slack)
end
