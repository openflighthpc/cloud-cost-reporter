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
  budget INTEGER,
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
  compute INTEGER,
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
