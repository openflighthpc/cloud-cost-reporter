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

require 'date'
require_relative './models/project_factory'

project = nil
start_date = nil
end_date = nil
rerun = ARGV.include?("rerun")
project = Project.find_by(name: ARGV[0])
if project == nil
  puts "Project with that name not found"
  return
end

valid = begin
  Date.parse(ARGV[1])
rescue ArgumentError
  false
end
if !valid
  puts "Provided start date invalid"
  return
end
start_date = valid

valid = begin
  Date.parse(ARGV[2])
rescue ArgumentError
  false
end
if !valid
  puts "Provided end date invalid"
  return
end
end_date = valid

if end_date <= start_date
  puts "End date must be after start date"
  return
end

if end_date > Project::DEFAULT_DATE
  puts "End date must be earlier than #{Project::DEFAULT_DATE}"
  return
end

puts "Recording logs."
puts "This may take some time (5+ mins per month of data). " if project.host == "azure"
begin
  project = ProjectFactory.new().as_type(project)
  project.record_logs_for_range(start_date, end_date, rerun)
rescue AzureApiError, AwsSdkError => e
  puts "Generation of logs for project #{project.name} stopped due to error: "
  puts e
  puts e.error_messages
  return
end
puts "Logs recorded."
