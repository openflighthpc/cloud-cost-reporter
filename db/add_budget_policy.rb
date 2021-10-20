require 'sqlite3'
load './models/project.rb'
load './models/aws_project.rb'

db = SQLite3::Database.open 'db/cost_tracker.sqlite3'

# we can't call it type as active record uses this for subclass casting
db.execute "ALTER TABLE budgets
ADD COLUMN policy TEXT NOT NULL DEFAULT 'budget_period';"

AwsProject.where(filter_level: "tag").each do |project|
  metadata = JSON.parse(project.metadata)
  if !metadata["budget_type"]
    metadata["budget_type"] = "budget_period"
  end
  project.metadata = metadata.to_json
  project.save!
end
