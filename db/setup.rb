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

db.execute "CREATE TABLE IF NOT EXISTS customers(
  name TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT
)"

db.execute "CREATE TABLE IF NOT EXISTS projects(
  name TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER,
  host TEXT,
  project_tag TEXT,
  filter_level TEXT,
  start_date TEXT,
  end_date TEXT,
  slack_channel TEXT,
  metadata TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS instance_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  host TEXT,
  instance_name TEXT,
  instance_id TEXT,
  instance_type TEXT,
  region TEXT,
  compute INTEGER,
  compute_group TEXT,
  status TEXT,
  timestamp TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS cost_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  cost REAL,
  currency TEXT,
  date TEXT,
  scope TEXT,
  timestamp TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS usage_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  scope TEXT,
  description TEXT,
  unit TEXT,
  amount REAL,
  start_date TEXT,
  end_date TEXT,
  timestamp TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS weekly_report_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  content TEXT,
  date TEXT,
  timestamp TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS instance_mappings(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  instance_type TEXT,
  customer_facing_name TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS budgets(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  amount INTEGER,
  effective_at TEXT,
  timestamp TEXT
)"
