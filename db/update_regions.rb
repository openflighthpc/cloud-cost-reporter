require 'sqlite3'
load './models/project.rb'
load './models/instance_log.rb'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

# move from having one region to multiple (aws only)
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

# populate historic instance log regions
logs = InstanceLog.includes(:project)
logs.each do |log|
  if log.region == nil
    log.region = log.project.aws? ? "eu-west-2" : "UK South"
    log.save!
  end
end