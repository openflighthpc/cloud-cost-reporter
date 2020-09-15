require 'active_record'

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
end
