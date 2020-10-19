#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
#
# This file is part of cloud-cost-reporter.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# cloud-cost-reporter is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with cloud-cost-reporter. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on cloud-cost-reporter, please visit:
# https://github.com/openflighthpc/cloud-cost-reporter
#==============================================================================

require 'json'
require 'date'
require 'sqlite3'
require_relative './models/project_factory'

def all_projects(date, slack, text, rerun, verbose, customer_facing)
  ProjectFactory.new().all_active_projects_as_type.each do |project|
    begin
      project.daily_report(date, slack, text, rerun, verbose, customer_facing)
    rescue AzureApiError, AwsSdkError => e
      puts "Generation of daily report for project #{project.name} stopped due to error: "
      puts e
      puts "_" * 50
    end
  end
end

date = Project::DEFAULT_DATE
project = nil
rerun = ARGV.include?("rerun")
slack = ARGV.include?("slack")
text = ARGV.include?("text")
customer_facing = ARGV.include?("customer")

if !(slack || text)
  slack = true
  text = true
end
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
  project = ProjectFactory.new().as_type(project)
  begin
    project.daily_report(date, slack, text, rerun, verbose, customer_facing)
  rescue AzureApiError, AwsSdkError => e
    puts "Generation of weekly report for project #{project.name} stopped due to error: "
    puts e
  end
else
  all_projects(date, slack, text, rerun, verbose, customer_facing)
end
