require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class CostLog < ActiveRecord::Base
  belongs_to :project

  def compute_cost
    (self.cost.to_f * 10).ceil
  end

  def risk_cost
    (compute_cost * 1.25).ceil
  end

  def fc_credits_cost
    (risk_cost.to_f / 2300).ceil
  end
end
