require 'sqlite3'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

db.execute "ALTER TABLE projects
ADD COLUMN user_id INTEGER;"
