require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class CostLog < ActiveRecord::Base
  belongs_to :project

  def usd_to_gbp
    ENV["USD_CONVERSION"] ? ENV["USD_CONVERSION"].to_f : 0.77
  end

  def compute_cost
    gbp_cost = self.currency == "USD" ? (self.cost.to_f * usd_to_gbp) : self.cost.to_f
    (gbp_cost * 10).ceil
  end

  def risk_cost
    (compute_cost.to_f * 1.25).ceil
  end

  def fc_credits_cost
    (risk_cost.to_f / 2300).ceil
  end
end
