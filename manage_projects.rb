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
require 'table_print'

def add_or_update_project(action=nil)
  factory = ProjectFactory.new
  if action == nil
    print "List, add or update project(s) (list/add/update)? "
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
    puts "regions: #{project.regions.join(", ")}" if project.aws?
    puts "location: #{project.location}" if project.azure?
    puts "resource_groups: #{project.resource_groups.join(", ")}" if project.azure?
    puts "slack_channel: #{project.slack_channel}"
    puts "metadata: (hidden)\n"
    update_attributes(project)
  elsif action == "add"
    add_project
  elsif action == "list"
    formatter = NoMethodMissingFormatter.new
    tp ProjectFactory.new().all_projects_as_type, :id, :name, :host, :budget, :start_date, :end_date,
    :slack_channel, {regions: {:display_method => :describe_regions, formatters: [formatter]}}, {location: {formatters: [formatter]}},
    {resource_groups: {:display_method => :describe_resource_groups, formatters: [formatter]}}, {filter_level: {formatters: [formatter]}}
    puts
    add_or_update_project
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
      puts "That is not a valid attribute for this project. Please try again."
    end
  end

  if attribute == "regions"
    update_regions(project)
  elsif attribute == "resource_groups" || attribute == "resource groups"
    update_resource_groups(project)
  else  
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
  end
  puts "Would you like to update another field (y/n)?"
  action = gets.chomp.downcase
  if action == "y"
    return update_attributes(project)
  end
end

def update_regions(project)
  metadata = JSON.parse(project.metadata)
  regions = project.regions
  puts "Regions: #{regions.join(", ")}"
  aws_regions = []
  file = File.open('aws_region_names.txt')
  file.readlines.each do |line|
    line = line.split(",")
    aws_regions << line[0]
  end
  stop = false
  valid = false
  while !stop
    while !valid
      puts "Add or delete region (add/delete)? "
      response = gets.chomp.downcase
      if response == "add"
        valid = true
        print "Add region (e.g. eu-central-1): "
        region = gets.chomp.downcase
        continue = false
        while !continue
          if !aws_regions.include?(region)
            puts "Warning: #{region} not found in list of valid aws regions. Do you wish to continue (y/n)? "
            response = gets.chomp.downcase
            if response == "n"
              return update_regions(project)
            elsif response != "y"
              puts "Invalid select, please try again"
            else
              continue = true
            end
          end
        end
        regions << region
        metadata[:regions] = regions.uniq
        project.metadata = metadata.to_json
        project.save!
        puts "Region added"
      elsif response == "delete"
        if regions.length > 1
          valid = true
          present = false
          while !present
            print "Region to delete: "
            to_delete = gets.chomp
            present = regions.include?(to_delete)
            if present
              regions.delete(to_delete)
              metadata["regions"] = regions
              project.metadata = metadata.to_json
              project.save!
              puts "Region deleted"
            else
              puts "Region #{to_delete} not present for this project"
            end
          end
        else
          puts "Cannot delete as must have at least one region"
        end
      else
        puts "Invalid response, please try again"
      end
    end
    yes_or_no = false
    while !yes_or_no
      print "Add/ delete another region (y/n)? "
      action = gets.chomp.downcase
      if action == "n"
        stop = true
        yes_or_no = true
      elsif action != "y"
        puts "Invalid option. Please try again"
      else
        puts "Regions: #{regions.join(", ")}"
        stop = false
        yes_or_no = true
        valid = false
      end
    end
  end
end

def update_resource_groups(project)
  metadata = JSON.parse(project.metadata)
  resource_groups = project.resource_groups
  puts "Resource groups: #{resource_groups.join(", ")}"
  stop = false
  valid = false
  while !stop
    while !valid
      puts "Add or delete resource group (add/delete)? "
      response = gets.chomp.downcase
      if response == "add"
        valid = true
        print "Add resource group: "
        group = gets.chomp.downcase
        continue = false
        resource_groups << group
        metadata[:resource_groups] = resource_groups.uniq
        project.metadata = metadata.to_json
        project.save!
        puts "Resource group added"
      elsif response == "delete"
        if resource_groups.length > 1
          valid = true
          present = false
          while !present
            print "Resource group to delete: "
            to_delete = gets.chomp.downcase
            present = resource_groups.include?(to_delete)
            if present
              resource_groups.delete(to_delete)
              metadata["resource_groups"] = resource_groups
              project.metadata = metadata.to_json
              project.save!
              puts "Resource group deleted"
            else
              puts "Resource group #{to_delete} not present for this project"
            end
          end
        else
          puts "Cannot delete as must have at least one resource group"
        end
      else
        puts "Invalid response, please try again"
      end
    end
    yes_or_no = false
    while !yes_or_no
      print "Add/ delete another resource group (y/n)? "
      action = gets.chomp.downcase
      if action == "n"
        stop = true
        yes_or_no = true
      elsif action != "y"
        puts "Invalid option. Please try again"
      else
        puts "Resource groups: #{resource_groups.join(", ")}"
        stop = false
        yes_or_no = true
        valid = false
      end
    end
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
  print "Budget (c.u./month): "
  attributes[:budget] = gets.chomp
  print "Slack Channel: "
  attributes[:slack_channel] = gets.chomp

  metadata = {}
  if attributes[:host].downcase == "aws"
    regions = []
    print "Primary region (e.g. eu-west-2): "
    regions << gets.chomp
    stop = false
    while !stop
      valid = false
      while !valid
        print "Additional regions (y/n)? "
        response = gets.chomp.downcase
        if response == "n"
          stop = true
          valid = true
        elsif response == "y"
          valid = true
        else
          puts "Invalid response. Please try again"
        end
      end
      if !stop
        print "Additional region (e.g. eu-central-1): "
        regions << gets.chomp
      end
    end
    metadata["regions"] = regions
    print "Access Key Id: "
    metadata["access_key_ident"] = gets.chomp
    print "Secret Access Key: "
    metadata["key"] = gets.chomp
    print "Account Id number: "
    metadata["account_id"] = gets.chomp
    print "Filtering level (tag/account): "
    metadata["filter_level"] = gets.chomp
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
    resource_groups = []
    print "First resource group name: "
    resource_groups << gets.chomp.downcase
    stop = false
    while !stop
      valid = false
      while !valid
        print "Additional resource groups (y/n)? "
        response = gets.chomp.downcase
        if response == "n"
          stop = true
          valid = true
        elsif response == "y"
          valid = true
        else
          puts "Invalid response. Please try again"
        end
      end
      if !stop
        print "Additional resource group name: "
        resource_groups << gets.chomp.downcase
      end
    end
    metadata["resource_groups"] = resource_groups
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

# for table print
class NoMethodMissingFormatter
  def format(value)
    value == "Method Missing" ? "n/a" : value
  end
end

tp.set :max_width, 100
add_or_update_project
