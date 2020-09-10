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
