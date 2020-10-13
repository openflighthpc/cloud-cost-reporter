load './models/project.rb'

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