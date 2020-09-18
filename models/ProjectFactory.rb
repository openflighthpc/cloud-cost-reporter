require_relative 'aws_project'
require_relative 'azure_project'
require_relative 'cost_log'
require_relative 'instance_log'

class ProjectFactory
  def all_projects_as_type
    Project.all.map { |project| as_type(project) }
  end

  def all_active_projects_as_type
    Project.active.map { |project| as_type(project) }
  end

  def as_type(project)
    project.aws? ? AwsProject.find(project.id) : AzureProject.find(project.id)
  end
end
