require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class Project < ActiveRecord::Base
  belongs_to :client
  
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

  def attributes
    {
      name: self.name,
      client_id: self.client_id,
      host: self.host,
      access_key_ident: self.access_key_ident,
      key: self.key,
      slack_channel: self.slack_channel
    }
  end

  def send_slack_message(msg)
    HTTParty.post("https://slack.com/api/chat.postMessage", headers: {"Authorization": "Bearer #{ENV['SLACK_TOKEN']}"}, body: {"text": msg, "channel": self.slack_channel, "as_user": true})
  end
end
