require 'httparty'
load './models/project.rb'

class AzureProject < Project
  after_initialize :construct_metadata

  def tenant_id
    @metadata['tenant_id']
  end

  def azure_client_id
    @metadata['client_id']
  end

  def subscription_id
    @metadata['subscription_id']
  end

  def client_secret
    @metadata['client_secret']
  end

  def bearer_token
    @metadata['bearer_token']
  end

  def bearer_expiry
    @metadata['bearer_expiry']
  end

  def get_cost_and_usage(date=Date.today-2)
    # refresh authorization token if necessary
    # tokens last for 3600 seconds (one hour)
    if Time.now.to_i > bearer_expiry.to_i
      update_bearer_token
    end

    cost_log = cost_logs.find_by(date: date.to_s)

    if !cost_log
      daily_cost = api_query_daily_cost(date)

      cost_log = CostLog.create(
        project_id: id,
        cost: daily_cost,
        currency: 'GBP',
        date: date.to_s,
        timestamp: Time.now.to_s
      )

      msg = "
        :moneybag: Usage for #{(Date.today - 2).to_s} :moneybag:
        *GBP:* #{cost_log.cost.to_f.ceil(2)}
        *Compute Units (Flat):* #{cost_log.compute_cost}
        *Compute Units (Risk):* #{cost_log.risk_cost}
        *FC Credits:* #{cost_log.fc_credits_cost}
      "

      send_slack_message(msg)
    end
  end

  def api_query_daily_cost(date)
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Consumption/usageDetails"
    query = {
      'api-version': '2019-10-01',
      '$filter': "properties/usageStart eq '#{date.to_s}' and properties/usageEnd eq '#{date.to_s}'"
    }
    response = HTTParty.get(
      uri,
      query: query,
      headers: { 'Authorization': "Bearer #{bearer_token}" }
    )

    if response.success?
      charges = response['value']
      # the query has multiple values that sound useful (effectivePrice, cost, 
      # quantity, unitPrice). 'cost' is the value that is used on the Azure Portal
      # Cost Analysis page (under 'Actual Cost') for the period selected.
      return charges.map { |c| c['properties']['cost'] }.reduce(:+)
    else
      raise RuntimeError, "Error querying Azure API. Error code #{response.code}."
    end
  end

  def update_bearer_token
    response = HTTParty.post(
      "https://login.microsoftonline.com/#{tenant_id}/oauth2/token",
      body: URI.encode_www_form(
        client_id: azure_client_id,
        client_secret: client_secret,
        resource: 'https://management.azure.com',
        grant_type: 'client_credentials',
      ),
      headers: {
        'Accept' => 'application/json'
      }
    )

    if response.success?
      db = SQLite3::Database.open 'db/cost_tracker.sqlite3'
      body = JSON.parse(response.body)
      @metadata['bearer_token'] = body['access_token']
      @metadata['bearer_expiry'] = body['expires_on']
      db.execute "UPDATE projects
                  SET metadata = '#{@metadata.to_json}'
                  WHERE id = #{id}"
    else
      raise RuntimeError, "Error obtaining new authorization token. Error code #{response.code}."
    end
  end

  private

  def construct_metadata
    @metadata = JSON.parse(metadata)
  end

end
