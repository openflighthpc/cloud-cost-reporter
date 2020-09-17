load './models/aws_project.rb'
load './models/azure_project.rb'

class ProjectFactory
  def all_projects_as_type
    Project.all.map { |project| as_type(project) }
  end

  def all_active_projects_as_type
    Project.all.select { |project| project.active? }.map { |project| as_type(project) }
  end

  def as_type(project)
    project.aws? ? AwsProject.new(project.attributes) : AzureProject.new(project.attributes)
  end
end
