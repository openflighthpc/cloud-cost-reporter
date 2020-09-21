require 'active_record'
require_relative 'instance_mapping'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class InstanceLog < ActiveRecord::Base
  belongs_to :project

  def customer_facing_type
    customer_facing = InstanceMapping.where(instance_type: self.instance_type)
    customer_facing.length > 0 ? customer_facing.first.customer_facing_name : "Compute (Other)"
  end
end
