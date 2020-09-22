require 'active_record'
require_relative 'weekly_report_log'
require_relative 'cost_log'
require_relative 'instance_log'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class Project < ActiveRecord::Base
  FIXED_MONTHLY_CU_COST = 5000
  belongs_to :customer
  has_many :cost_logs
  has_many :instance_logs
  has_many :weekly_report_logs

  validates :name, presence: true, uniqueness: true
  validates :slack_channel, presence: true
  validates :budget, numericality: true
  validates :start_date, presence: true
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
    return true if !self.end_date
    Date.parse(self.end_date) > Date.today
  end

  def get_cost_and_usage(date=Date.today - 2, slack=true, rerun=false)
  end

  def get_forecasts
  end

  def record_instance_logs(rerun=false)
  end

  def record_cost_log
  end

  def weekly_report(date=Date.today, slack=true, rerun=false)
  end

  def get_data_out(date=Date.today - 2)
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
    Date.parse(date) rescue false
  end
end
