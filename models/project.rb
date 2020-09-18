require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class Project < ActiveRecord::Base
  belongs_to :customer
  has_many :cost_logs
  has_many :instance_logs

  validates :name, presence: true, uniqueness: true
  validates :slack_channel, presence: true
  validates :start_date, presence: true
  validate :start_date_valid, on: [:update, :create]
  validate :end_date_valid, on: [:update, :create], if: -> { end_date != nil }
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

  def get_cost_and_usage
  end

  def get_forecasts
  end

  def record_instance_logs
  end

  def record_cost_log
  end

  def weekly_report
  end

  def attributes
    {
      name: self.name,
      id: self.id,
      client_id: self.client_id,
      host: self.host,
      slack_channel: self.slack_channel,
      budget: self.budget,
      start_date: self.start_date,
      metadata: self.metadata,
    }
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

  def date_valid?(date)
    Date.parse(date) rescue false
  end
end
