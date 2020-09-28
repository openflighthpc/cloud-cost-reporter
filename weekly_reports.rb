require 'json'
require 'date'
require 'sqlite3'
require_relative './models/project_factory'

def all_projects(date, slack, rerun, verbose)
  ProjectFactory.new().all_projects_as_type.each do |project|
    begin
      project.weekly_report(date, slack, rerun, verbose)
    rescue AzureApiError => e
      puts e
    end
  end
end

date = Date.today - 2
project = nil
rerun = ARGV.include?("rerun")
slack = !ARGV.include?("text")
verbose = false
if ARGV.include?("verbose")
  ARGV.delete("verbose")
  verbose = true
end

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
  begin
    project = ProjectFactory.new().as_type(project)
    project.weekly_report(date, slack, rerun, verbose)
  rescue AzureApiError => e
    puts e
  end
else
  all_projects(date, slack, rerun, verbose)
end
