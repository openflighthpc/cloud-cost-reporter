require_relative './models/project_factory'

def add_or_update_project(action=nil)
  factory = ProjectFactory.new
  if action == nil
    print "Add or update project (add/update)? "
    action = gets.chomp.downcase
  end
  if action == "update"
    print "Project name: "
    project_name = gets.chomp
    project = factory.as_type(Project.find_by_name(project_name))
    if project == nil
      puts "Project not found. Please try again."
      return add_or_update_project("update")
    end
    puts project.name
    puts "host: #{project.host}"
    puts "start_date: #{project.start_date}"
    puts "end_date: #{project.end_date}"
    puts "budget: #{project.budget}"
    puts "slack_channel: #{project.slack_channel}"
    puts "metadata: (hidden)\n"
    update_attributes(project)
  elsif action == "add"
    add_project
  else
    puts "Invalid selection, please try again."
    add_or_update_project
  end
end

def update_attributes(project)
  valid = false
  attribute = nil
  while !valid
    puts "What would you like to update (for security related attributes please select metadata)? "
    attribute = gets.chomp
    if project.respond_to?(attribute.downcase)
      valid = true
    else
      "That is not a valid attribute for this project. Please try again."
    end
  end

  if attribute == "metadata"
    metadata = JSON.parse(project.metadata)
    print "Key name: "
    key = gets.chomp
    print 'Value: '
    value = gets.chomp
    metadata[key] = value
    project.metadata = metadata.to_json
  else
    print 'Value: '
    value = gets.chomp
    project.write_attribute(attribute.to_sym, value)
  end
  valid = project.valid?
  while !valid
    project.errors.messages.each do |k, v|
      puts "#{k} #{v.join("; ")}"
      puts "Please enter new #{k}"
      value = gets.chomp
      project.write_attribute(k, value)
    end
    valid = project.valid?
  end
  project.save!
  puts "#{attribute} updated successfully"
  puts "Would you like to update another field (y/n)?"
  action = gets.chomp.downcase
  if action == "y"
    return update_attributes(project)
  end
end

def add_project
  attributes = {}
  print "Project name: "
  attributes[:name] = gets.chomp
  print "Host (aws or azure): "
  attributes[:host] = gets.chomp.downcase
  print "Start date (YYYY-MM-DD): "
  attributes[:start_date] = gets.chomp
  print "Budget (c.u.): "
  attributes[:budget] = gets.chomp
  print "Slack Channel: "
  attributes[:slack_channel] = gets.chomp

  metadata = {}
  if attributes[:host].downcase == "aws"
    print "Access Key Id: "
    metadata["access_key_ident"] = gets.chomp
    print "Secret Access Key: "
    metadata["key"] = gets.chomp
    print "Account Id number: "
    metadata["account_id"] = gets.chomp
    print "Filtering level (tag/account): "
    metadata["filter_level"] = gets.chomp
  else
    print "Tenant Id: "
    metadata["tenant_id"] = gets.chomp
    print "Azure Client Id: "
    metadata["client_id"] = gets.chomp
    print "Subscription Id: "
    metadata["subscription_id"] = gets.chomp
    print "Client Secret: "
    metadata["client_secret"] = gets.chomp
  end
  attributes[:metadata] = metadata.to_json
  
  project = Project.new(attributes)
  valid = project.valid?
  while !valid
    project.errors.messages.each do |k, v|
      puts "#{k} #{v.join("; ")}"
      puts "Please enter new #{k}"
      value = gets.chomp
      project.write_attribute(k, value)
    end
    valid = project.valid?
  end
  project.save
  puts "Project #{project.name} created"
end

add_or_update_project
