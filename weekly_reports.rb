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
slack = true
project = nil

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
  project.weekly_report(date, slack, rerun)
else
  all_projects(date, slack, rerun)
end
