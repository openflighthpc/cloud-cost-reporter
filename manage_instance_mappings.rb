require_relative './models/instance_mapping'

def add_or_update_mapping(action=nil)
  if action == nil
    print "Add, update or delete customer facing instance name (add/update/delete)? "
    action = gets.chomp.downcase
  end
  if action == "update" || action == "delete"
    print "Instance type name: "
    type_name = gets.chomp
    mapping = InstanceMapping.find_by(instance_type: type_name)
    if mapping == nil
      puts "Mapping for that instance type not found. Please try again."
      return add_or_update_mapping(action)
    end
    puts "Customer facing name: #{mapping.customer_facing_name}"
    action == "update" ? update_attributes(mapping) : delete_mapping(mapping)
  elsif action == "add"
    add_mapping
  else
    puts "Invalid selection, please try again."
    add_or_update_mapping
  end
end

def update_attributes(mapping)
  valid = false
  attribute = nil
  while !valid
    puts "What would you like to update (type/name)? "
    attribute = gets.chomp
    if ["type", "name"].include?(attribute)
      valid = true
    else
      "That is not a valid attribute. Please try again."
    end
  end

  attribute = attribute == "type" ? :instance_type : :customer_facing_name
  print 'Value: '
  value = gets.chomp
  mapping.write_attribute(attribute, value)
  valid = mapping.valid?
  while !valid
    mapping.errors.messages.each do |k, v|
      puts "#{k} #{v.join("; ")}"
      puts "Please enter new #{k}"
      value = gets.chomp
      mapping.write_attribute(k, value)
    end
    valid = mapping.valid?
  end
  mapping.save!
  puts "#{attribute} updated successfully"
  print "Would you like to update another field (y/n)? "
  action = gets.chomp.downcase
  if action == "y"
    return update_attributes(mapping)
  end
end

def add_mapping
  attributes = {}
  print "Instance type name: "
  attributes[:instance_type] = gets.chomp
  print "Customer facing name: "
  attributes[:customer_facing_name] = gets.chomp

  mapping = InstanceMapping.new(attributes)
  valid = mapping.valid?
  while !valid
    mapping.errors.messages.each do |k, v|
      puts "#{k} #{v.join("; ")}"
      puts "Please enter new #{k}"
      value = gets.chomp
      mapping.write_attribute(k, value)
    end
    valid = mapping.valid?
  end
  mapping.save!
  puts "Mapping #{mapping.instance_type} to #{mapping.customer_facing_name} created"
end

def delete_mapping(mapping)
  print "Are you sure you want to delete the mapping for instance type #{mapping.instance_type}? (y/n) "
  valid = false
  while !valid
    response = gets.chomp.downcase
    if ["y", "n"].include?(response)
      valid = true
    else
      print "That is not a valid response. Please enter 'y' or 'n' "
    end
  end
  if response == 'y'
    mapping.delete
    puts "Mapping for instance type #{mapping.instance_type} deleted"
  end
end

add_or_update_mapping
