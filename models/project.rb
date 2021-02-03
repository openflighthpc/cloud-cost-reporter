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
require 'httparty'
require_relative 'weekly_report_log'
require_relative 'cost_log'
require_relative 'instance_log'
require_relative 'usage_log'
require_relative 'budget'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class Project < ActiveRecord::Base
  FIXED_MONTHLY_CU_COST = 5000
  DEFAULT_DATE = Date.today - 3
  belongs_to :customer
  has_many :cost_logs
  has_many :instance_logs
  has_many :weekly_report_logs
  has_many :usage_logs
  has_many :budgets

  validates :name, presence: true, uniqueness: true
  validates :slack_channel, presence: true
  validates :start_date, presence: true
  validates :filter_level, presence: true
  validate :start_date_valid, on: [:update, :create]
  validate :end_date_valid, on: [:update, :create], if: -> { end_date != nil }
  validate :end_date_after_start, on: [:update, :create], if: -> { end_date != nil }
  validates :host,
    presence: true,
    inclusion: {
      in: %w(aws azure),
      message: "%{value} is not a valid host"
    }
  scope :active, -> { 
    where("end_date > ? OR end_date IS NULL", Date.today).where(
          "start_date <= ?", Date.today)
  }
  
  def aws?
    self.host.downcase == "aws"
  end

  def azure?
    self.host.downcase == "azure"
  end

  def active?
    Date.parse(self.start_date) <= Date.today &&
    (!self.end_date || Date.parse(self.end_date) > Date.today)
  end

  def current_budget
    return 0 if !active?

    latest = self.budgets.where("effective_at <= ? ", Date.today).last
    latest ? latest.amount : 0
  end

  def daily_report(date=DEFAULT_DATE, slack=true, text=true, rerun=false, verbose=false, customer_facing=false)
  end

  def get_forecasts
  end

  def record_instance_logs(rerun=false)
  end

  def record_cost_log
  end

  def weekly_report(date=DEFAULT_DATE, slack=true, text=true, rerun=false, verbose=false, customer_facing=true)
  end

  def get_data_out(date=DEFAULT_DATE)
  end

  def get_ssd_usage
  end

  def fixed_daily_cu_cost
    FIXED_MONTHLY_CU_COST / Time.now.end_of_month.day
  end

  def send_slack_message(msg)
    HTTParty.post("https://slack.com/api/chat.postMessage", headers: {"Authorization": "Bearer #{ENV['SLACK_TOKEN']}"}, body: {"text": msg, "channel": self.slack_channel, "as_user": true})
  end

  private

  def start_date_valid
    errors.add(:start_date, "Must be a valid date") if !date_valid?(self.start_date)
  end

  def end_date_valid
    errors.add(:end_date, "Must be a valid date") if !date_valid?(self.end_date)
  end

  def end_date_after_start
    starting = date_valid?(self.start_date)
    ending = date_valid?(self.end_date)
    if starting && ending && ending <= starting    
      errors.add(:end_date, "Must be after start date")
    end
  end

  def date_valid?(date)
    begin
      Date.parse(date)
    rescue ArgumentError
      false
    end
  end
end
