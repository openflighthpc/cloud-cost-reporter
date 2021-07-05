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

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

db.execute "ALTER TABLE projects RENAME TO projects_old;"
db.execute "CREATE TABLE projects(
              name TEXT,
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              host TEXT,
              project_tag TEXT,
              filter_level TEXT,
              start_date TEXT,
              end_date TEXT,
              slack_channel TEXT,
              metadata TEXT
            );"
db.execute "INSERT INTO projects (name, id, host, project_tag, filter_level, start_date, end_date, slack_channel, metadata)
            SELECT name, id, host, project_tag, filter_level, start_date, end_date, slack_channel, metadata
            FROM projects_old;
            DROP TABLE projects_old;
            COMMIT;"
