require 'json'
require 'httparty'
require 'date'
require 'sqlite3'
require_relative './models/ProjectFactory'

ProjectFactory.new().all_active_projects_as_type.each do |project|
  project.weekly_report
end
