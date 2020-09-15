load './models/project.rb'

def add_budget
  print "Project name: "
  project_name = gets.chomp
  project = Project.find_by_name(project_name)
  if project == nil
    puts "Project not found. Please try again."
    return add_budget
  end
  current_budget = project.budget ? "#{project.budget} compute units" : "none"
  puts "Current budget: #{current_budget}"
  success = false
  invalid = false
  while success == false
    puts "Please provide a valid number" if invalid == true
    print"New budget (compute units): "
    budget = gets.chomp
    invalid = Integer(budget) rescue true
    next if invalid == true
    project.budget = budget
    success = project.save!
  end
  
  puts "Budget set to #{budget} compute units for project #{project_name}"
end

add_budget