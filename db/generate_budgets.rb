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
load './models/project.rb'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

db.execute "CREATE TABLE IF NOT EXISTS budgets(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  amount INTEGER,
  effective_at TEXT,
  timestamp TEXT
  )"

Project.all.each do |project|
  if project.budgets.length == 0
    Budget.create(
    {
      project_id: project.id,
      amount: project.budget,
      effective_at: project.start_date,
      timestamp: Time.now
    })
  end
end

if Project.first.budget != nil
  db.execute "ALTER TABLE projects RENAME TO projects_old;"
  db.execute "CREATE TABLE projects( 
      name TEXT,
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER,
      host TEXT,
      start_date TEXT,
      end_date TEXT,
      slack_channel TEXT,
      metadata TEXT
    );"
  db.execute "INSERT INTO projects (name, id, client_id, host, start_date, end_date, slack_channel, metadata)
    SELECT name, id, client_id, host, start_date, end_date, slack_channel, metadata
    FROM projects_old;
    DROP TABLE projects_old;
    COMMIT;"
end
