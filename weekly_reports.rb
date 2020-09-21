require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
require_relative './models/project_factory'

def all_projects(date, slack, rerun)
  ProjectFactory.new().all_projects_as_type.each do |project|
    project.weekly_report(date, slack, rerun)
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

rerun = false
if ARGV[3] && ARGV[3] == "rerun"
  rerun = true
end

if ARGV[0] && ARGV[0] != "all"  
  project = Project.find_by(name: ARGV[0])
  if project == nil
    puts "Project with that name not found"
    return
  end
  project = ProjectFactory.new().as_type(project)
  project.weekly_report(date, slack, rerun)
else
  all_projects(date, slack, rerun)
end
