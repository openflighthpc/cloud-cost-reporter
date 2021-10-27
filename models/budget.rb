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

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3',  timeout: 3000)

class Budget < ActiveRecord::Base
  belongs_to :project
  default_scope { order(:effective_at, timestamp: :asc) }
  validates :effective_at, :policy, presence: true
  validates :policy, inclusion: {
      in: ["monthly", "continuous"],
      message: "%{value} is not a valid budget policy. Must be monthly or continuous."
    }
  validate :effective_at_valid, on: [:update, :create]
  validate :has_total_or_month
  validate :monthly_less_than_total
  validate :monthly_policy_has_limit
  validate :continuous_policy_has_total

  # prevents weekly reports breaking
  def amount
    policy == "monthly" ? monthly_limit : total_amount
  end

  private

  def total_or_month
    if !total_amount && !monthly_limit
      errors.add(:monthly_limit, "or a total amount must be defined")
    end
  end

  def monthly_less_than_total
    if monthly_limit && total_amount && monthly_limit > total_amount
      errors.add(:monthly_limit, "must be less than total amount")
    end
  end

  def monthly_policy_has_limit
    if policy == "monthly" && !monthly_limit
      errors.add(:monthly_limit, "must be set for a monthly budget")
    end
  end

  def continuous_policy_has_total
    if policy == "continuous" && !total_amount
      errors.add(:total_amount, "must be set for continuous budget")
    end
  end

  def effective_at_valid
    begin
      Date.parse(self.effective_at)
    rescue ArgumentError
      errors.add(:effective_at, "Must be a valid date")
    end
  end
end
