require 'sqlite3'
load './models/project.rb'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

Project.where(host: "aws").each do |project|
  metadata = JSON.parse(project.metadata)
  regions = metadata["regions"]
  regions ||= []
  if metadata.has_key?("region")
    regions << metadata["region"]
  end
  metadata["regions"] = regions.uniq
  metadata.delete("region")
  project.metadata = metadata.to_json
  project.save!
end

db.execute "ALTER TABLE instance_logs ADD COLUMN region TEXT" rescue puts "column already added (no further action required)"
