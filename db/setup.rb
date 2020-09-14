require 'sqlite3'
load './models/project.rb'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

db.execute "CREATE TABLE IF NOT EXISTS clients(
  name TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT
)"

db.execute "CREATE TABLE IF NOT EXISTS projects(
  name TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER,
  host TEXT,
  access_key_ident TEXT,
  key TEXT,
  slack_channel TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS instance_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  instance_name TEXT,
  instance_id TEXT,
  instance_type TEXT,
  status TEXT,
  timestamp TEXT
)"

db.execute "CREATE TABLE IF NOT EXISTS cost_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  cost REAL,
  currency TEXT,
  date TEXT,
  timestamp TEXT
)"
