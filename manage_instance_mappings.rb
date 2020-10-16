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

require_relative './models/instance_mapping'
require 'table_print'

def add_or_update_mapping
  valid_action = false
  while !valid_action
    print "List, add, update or delete customer facing instance name(s) (list/add/update/delete)? "
    action = gets.chomp.downcase
    if action == "update" || action == "delete"
      valid_action = true
      mapping = nil
      while !mapping
        print "Instance type name: "
        type_name = gets.chomp
        mapping = InstanceMapping.find_by(instance_type: type_name)
        if mapping == nil
          puts "Mapping for that instance type not found. Please try again."
        end
      end
      puts "Customer facing name: #{mapping.customer_facing_name}"
      action == "update" ? update_attributes(mapping) : delete_mapping(mapping)
    elsif action == "add"
      valid_action = true
      add_mapping
    elsif action == "list"
      tp InstanceMapping.all
      puts
    else
      puts "Invalid selection, please try again."
    end
  end
end

def update_attributes(mapping)
  stop = false
  while !stop
    valid = false
    attribute = nil
    while !valid
      puts "What would you like to update (type/name)? "
      attribute = gets.chomp
      if ["type", "name"].include?(attribute)
        valid = true
      else
        puts "That is not a valid attribute. Please try again."
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
    if action == "n"
      stop = true
    end
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
