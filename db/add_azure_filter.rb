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
require 'sqlite3'
load './models/project_factory.rb'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

db.execute "ALTER TABLE projects
ADD COLUMN filter_level TEXT;"

AzureProject.all.each do |project|
  if !project.filter_level
    project.filter_level = "resource group"
    project.save!
  end
end

Project.all.each do |project|
  metadata = JSON.parse(project.metadata)
  filter = metadata["filter_level"]
  if filter
    project.filter_level = filter
    metadata.delete("filter_level")
    project.metadata = metadata.to_json
    project.save!
  end
end
