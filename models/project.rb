require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class Project < ActiveRecord::Base
  belongs_to :client
  has_many :cost_logs
  has_many :instance_logs
  
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
      start_date: self.start_date,
      metadata: JSON.parse(self.metadata),
    }
  end

  def send_slack_message(msg)
    HTTParty.post("https://slack.com/api/chat.postMessage", headers: {"Authorization": "Bearer #{ENV['SLACK_TOKEN']}"}, body: {"text": msg, "channel": self.slack_channel, "as_user": true})
  end
end
