#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
#
# This file is part of cloud-cost-reporter.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# cloud-cost-reporter is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with cloud-cost-reporter. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on cloud-cost-reporter, please visit:
# https://github.com/openflighthpc/cloud-cost-reporter
#==============================================================================

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
    project = Project.find_by_name(project_name)
    if project == nil
      puts "Project not found. Please try again."
      return add_or_update_project("update")
    end
    project = factory.as_type(project)
    puts project.name
    puts "host: #{project.host}"
    puts "start_date: #{project.start_date}"
    puts "end_date: #{project.end_date}"
    puts "budget: #{project.budget}c.u./month"
    puts "region: #{project.region}" if project.aws?
    puts "location: #{project.location}" if project.azure?
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
  valid_date = false
  while !valid_date
    print "Start date (YYYY-MM-DD): "
    valid_date = Date.parse(gets.chomp) rescue false
    if valid_date
      attributes[:start_date] = valid_date
    else
      puts "Invalid date. Please ensure it is in the format YYYY-MM-DD"
    end
  end
  valid_date = false
  while !valid_date
    print "End date (YYYY-MM-DD). Press enter to leave blank: "
    date = gets.chomp
    break if date == ""
    valid_date = Date.parse(date) rescue false
    if valid_date
      attributes[:start_date] = valid_date
    else
      puts "Invalid date. Please ensure it is in the format YYYY-MM-DD"
    end
  end
  print "Budget (c.u./month): "
  attributes[:budget] = gets.chomp
  print "Slack Channel: "
  attributes[:slack_channel] = gets.chomp

  metadata = {}
  if attributes[:host].downcase == "aws"
    print "Region (e.g. eu-west-2): "
    metadata["region"] = gets.chomp
    print "Access Key Id: "
    metadata["access_key_ident"] = gets.chomp
    print "Secret Access Key: "
    metadata["key"] = gets.chomp
    print "Account Id number: "
    metadata["account_id"] = gets.chomp
    valid = false
    while !valid
      print "Filtering level (tag/account): "
      response = gets.strip.downcase
      if ["tag", "account"].include?(response)
        valid = true
        metadata["filter_level"] = response
      else
        puts "Invalid selection. Please enter tag or account"
      end
    end
  else
    print "Location (e.g. UK South): "
    metadata["location"] = gets.chomp
    print "Tenant Id: "
    metadata["tenant_id"] = gets.chomp
    print "Azure Client Id: "
    metadata["client_id"] = gets.chomp
    print "Subscription Id: "
    metadata["subscription_id"] = gets.chomp
    print "Client Secret: "
    metadata["client_secret"] = gets.chomp
    print "Resource group name: "
    metadata["resource_group"] = gets.chomp
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
