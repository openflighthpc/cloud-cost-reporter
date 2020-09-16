require 'json'
require 'sqlite3'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

db.execute "ALTER TABLE projects
            ADD COLUMN metadata TEXT;"

db.execute "SELECT * FROM projects" do |row|
  metadata = { 'key' => row[6], 'access_key_ident' => row[5], 'region' => row[4] }
  db.execute "UPDATE projects
              SET metadata = '#{metadata.to_json}'
              WHERE id = #{row[1]};"
end

db.execute "BEGIN TRANSACTION;
            CREATE TEMPORARY TABLE projects_backup(name,id,client_id,host,slack_channel,metadata);
            INSERT INTO projects_backup SELECT name,id,client_id,host,slack_channel,metadata FROM projects;
            DROP TABLE projects;
            CREATE TABLE projects(name,id,client_id,host,slack_channel,metadata);
            INSERT INTO projects SELECT name,id,client_id,slack_channel,metadata FROM projects_backup;
            DROP TABLE projects_backup;
            COMMIT;
          "
