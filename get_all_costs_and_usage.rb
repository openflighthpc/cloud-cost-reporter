require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
require_relative './models/project_factory'

def all_projects(date, slack, rerun)
  ProjectFactory.new().all_projects_as_type.each do |project|
    project.record_instance_logs(rerun)
    project.get_cost_and_usage(date, slack, rerun)
    #project.each_instance_usage_data
    #project.get_instance_usage_data("i-062dd1030e63f9cff")
    #project.get_data_out(date)
    #project.get_ssd_usage
    #puts project.get_cost_per_hour('r5.2xlarge')
  end
end

date = Date.today - 2
project = nil
rerun = ARGV.include?("rerun")
slack = !ARGV.include?("text")

if ARGV[1] && ARGV[1] != "latest"
  valid = Date.parse(ARGV[1]) rescue false
  if !valid
    puts "Provided date invalid"
    return
  end
  date = valid
end
    
if ARGV[0] && ARGV[0] != "all"  
  project = Project.find_by(name: ARGV[0])
  if project == nil
    puts "Project with that name not found"
    return
  end
  project = ProjectFactory.new().as_type(project)
  project.record_instance_logs
  project.get_cost_and_usage(date, slack, rerun)
else
  all_projects(date, slack, rerun)
end
