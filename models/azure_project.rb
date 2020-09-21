require_relative 'project'
require 'pp'

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

  def get_cost_and_usage(date=Date.today-2, slack=true, rerun=false)
    cost_log = cost_logs.find_by(date: date.to_s)

    # refresh authorization token if necessary
    # tokens last for 3600 seconds (one hour)
    if Time.now.to_i > bearer_expiry.to_i
      update_bearer_token
    end

    total_cost_log = cost_logs.find_by(date: date.to_s)
    cached = total_cost_log && !rerun

    if !total_cost_log || rerun
      response = api_query_daily_cost(date)
      # the query has multiple values that sound useful (effectivePrice, cost, 
      # quantity, unitPrice). 'cost' is the value that is used on the Azure Portal
      # Cost Analysis page (under 'Actual Cost') for the period selected.
      daily_cost = response.map { |c| c['properties']['cost'] }.reduce(:+)

      if rerun && total_cost_log
        total_cost_log.assign_attributes(cost: daily_cost, timestamp: Time.now.to_s)
      else
        total_cost_log = CostLog.create(
          project_id: id,
          cost: daily_cost,
          currency: 'GBP',
          scope: 'total',
          date: date.to_s,
          timestamp: Time.now.to_s
        )
      end
    end

<<<<<<< HEAD
    msg = [
        "#{"*Cached report*" if cached}",
        ":moneybag: Usage for #{date.to_s} :moneybag:",
        "*GBP:* #{total_cost_log.cost.to_f.ceil(2)}",
        "*Compute Units (Flat):* #{total_cost_log.compute_cost}",
        "*Compute Units (Risk):* #{total_cost_log.risk_cost}",
        "*FC Credits:* #{total_cost_log.fc_credits_cost}"
      ].join("\n") + "\n"
    send_slack_message(msg) if slack

    puts "\nProject: #{self.name}\n"
    puts msg.gsub(":moneybag:", "").gsub("*", "")
    puts "_" * 50
=======
    response = api_query_vm_view
    overall_usage=""

    api_query_vm_view.each do |vm|
      name = vm['id'].match(/virtualMachines\/(.*)\/providers/)[1]
      status = case vm['properties']['availabilityState']
               when 'Unavailable'
                 ' (powered off)'
               when 'Available'
                 ''
               else
                 ' (status unknown)'
               end
      overall_usage << "\n\t\t\t\t#{name} #{status}"
    end

    msg = "
      :moneybag: Usage for #{(Date.today - 2).to_s} :moneybag:
      *GBP:* #{cost_log.cost.to_f.ceil(2)}
      *Compute Units (Flat):* #{cost_log.compute_cost}
      *Compute Units (Risk):* #{cost_log.risk_cost}
      *FC Credits:* #{cost_log.fc_credits_cost}
      *Compute Instance Usage:* #{overall_usage}
    "

    send_slack_message(msg)
>>>>>>> 48c224c... Add output section for VM status
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
      return response['value']
    else
      puts "Error querying daily cost Azure API for project #{name}. Error code #{response.code}."
    end
  end

  def api_query_vm_view
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/jacks-resource-group/providers/Microsoft.ResourceHealth/availabilityStatuses"
    query = {
      'api-version': '2020-05-01',
      '$filter': "resourceType eq 'Microsoft.Compute/virtualMachines'"
    }
    response = HTTParty.get(
      uri,
      query: query,
      headers: { 'Authorization': "Bearer #{bearer_token}" }
    )

    if response.success?
      return response['value']
    else
      puts "Error querying node status Azure API for project #{name}. Error code #{response.code}."
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
      body = JSON.parse(response.body)
      @metadata['bearer_token'] = body['access_token']
      @metadata['bearer_expiry'] = body['expires_on']
      self.metadata = @metadata.to_json
      self.save
    else
      puts "Error obtaining new authorization token for project #{name}. Error code #{response.code}."
    end
  end

  private

  def construct_metadata
    @metadata = JSON.parse(metadata)
  end

end
