require 'active_record'
load './models/instance_mapping.rb'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class InstanceLog < ActiveRecord::Base
  belongs_to :project

  def compute_node?
    %w(gateway gw GW cadmin chead monitor).each do |word|
      if self.instance_name.include?(word)
        return false
      end
    end
    true
  end

  def customer_facing_type
    customer_facing = InstanceMapping.where(instance_type: self.instance_type)
    customer_facing.length > 0 ? customer_facing.first.customer_facing_name : "Compute (Other)"
  end
end
