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

require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class CostLog < ActiveRecord::Base
  USD_GBP_CONVERSION = ENV['USD_GBP_CONVERSION'] ? ENV['USD_GBP_CONVERSION'].to_f : 0.77
  belongs_to :project

  def compute_cost
    gbp_cost = self.currency == "USD" ? (self.cost.to_f * USD_GBP_CONVERSION) : self.cost.to_f
    (gbp_cost * 10).ceil
  end

  def risk_cost
    (compute_cost.to_f * 1.25).ceil
  end

  def fc_credits_cost
    (risk_cost.to_f / 2300).ceil
  end
end
