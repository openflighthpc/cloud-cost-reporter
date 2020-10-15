require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class UsageLog < ActiveRecord::Base
  belongs_to :project

  def customer_facing_type
    if description != "data_out"
      customer_facing = InstanceMapping.find_by(instance_type: self.description)
      customer_facing ? customer_facing.first.customer_facing_name : "Compute (Other)"
    end
  end
end
