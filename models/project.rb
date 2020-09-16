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
  validates :host,
    presence: true,
    inclusion: {
      in: %w(aws azure),
      message: "%{value} is not a valid host"
    }
  
  def aws?
    self.host.downcase == "aws"
  end

  def azure?
    self.host.downcase == "azure"
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
      access_key_ident: self.access_key_ident,
      key: self.key,
      slack_channel: self.slack_channel,
      budget: self.budget,
      start_date: self.start_date
    }
  end

  def send_slack_message(msg)
    HTTParty.post("https://slack.com/api/chat.postMessage", headers: {"Authorization": "Bearer #{ENV['SLACK_TOKEN']}"}, body: {"text": msg, "channel": self.slack_channel, "as_user": true})
  end

  private

  def start_date_valid
    valid = Date.parse(self.start_date) rescue false
    if !valid
      errors.add(:start_date, "Must be a valid date")
    end
  end 
end
