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

db.execute "ALTER TABLE budgets RENAME TO budgets_old;"
db.execute "CREATE TABLE budgets(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  monthly_limit INTEGER,
  total_amount INTEGER,
  policy TEXT DEFAULT 'monthly',
  effective_at TEXT,
  timestamp TEXT
)"

db.execute "INSERT INTO budgets (id, project_id, monthly_limit, effective_at, timestamp)
            SELECT id, project_id, amount, effective_at, timestamp
            FROM budgets_old;
            DROP TABLE budgets_old;
            COMMIT;"
