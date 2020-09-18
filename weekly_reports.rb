require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
load './models/ProjectFactory.rb'


ProjectFactory.new().all_active_projects_as_type.each do |project|
  project.weekly_report
end
