require_relative 'project'
require 'pp'

class AzureProject < Project
  after_initialize :construct_metadata
  after_initialize :refresh_auth_token
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

  def today_compute_nodes
    @today_compute_nodes ||= api_query_compute_nodes
  end

  def historic_compute_nodes(date)
    self.instance_logs.where("timestamp LIKE ?", "%#{date}%").where(compute: 1) 
  end

  def resource_group
    @metadata['resource_group']
  end

  def get_cost_and_usage(date=Date.today-2, slack=true, rerun=false)
    record_instance_logs(rerun) if date >= Date.today - 2 && date <= Date.today
    cost_log = cost_logs.find_by(date: date.to_s)

    total_cost_log = cost_logs.find_by(date: date.to_s, scope: "total")
    compute_cost_log = cost_logs.find_by(date: date.to_s, scope: "compute")
    cached = total_cost_log && !rerun

    if !total_cost_log || !compute_cost_log || rerun
      response = api_query_cost(date)
      # the query has multiple values that sound useful (effectivePrice, cost, 
      # quantity, unitPrice). 'cost' is the value that is used on the Azure Portal
      # Cost Analysis page (under 'Actual Cost') for the period selected.
      daily_cost = begin
                     response.map { |c| c['properties']['cost'] }.reduce(:+)
                   rescue NoMethodError
                     0.0
                   end

      response.select! { |cd| historic_compute_nodes(date).any? { |node| node.instance_name == cd['properties']['resourceName'] } }
      compute_cost = begin
                     response.map { |c| c['properties']['cost'] }.reduce(:+)
                   rescue NoMethodError
                     0.0
                   end

      if rerun && total_cost_log
        total_cost_log.assign_attributes(cost: daily_cost, timestamp: Time.now.to_s)
        total_cost_log.save!
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

      if rerun && compute_cost_log
        compute_cost_log.assign_attributes(cost: compute_cost, timestamp: Time.now.to_s)
        compute_cost_log.save!
      else
        compute_cost_log = CostLog.create(
          project_id: id,
          cost: compute_cost,
          currency: 'GBP',
          scope: 'compute',
          date: date.to_s,
          timestamp: Time.now.to_s
        )
      end
    end

    overall_usage = get_overall_usage(date)

    msg = [
        "#{"*Cached report*" if cached}",
        ":moneybag: Usage for #{date.to_s} :moneybag:",
        "*Compute Cost (GBP):* #{compute_cost_log.cost.to_f.ceil(2)}",
        "*Compute Units (Flat):* #{compute_cost_log.compute_cost}",
        "*Compute Units (Risk):* #{compute_cost_log.risk_cost}\n",
        "*Total Cost (GBP):* #{total_cost_log.cost.to_f.ceil(2)}",
        "*Total Compute Units (Flat):* #{total_cost_log.compute_cost}",
        "*Total Compute Units (Risk):* #{total_cost_log.risk_cost}\n",
        "*FC Credits:* #{total_cost_log.fc_credits_cost}",
        "*Compute Instance Usage:* #{overall_usage}"
      ].join("\n") + "\n"
    send_slack_message(msg) if slack

    puts "\nProject: #{self.name}\n"
    puts msg.gsub(":moneybag:", "").gsub("*", "")
    puts "_" * 50
  end

  def weekly_report(date=Date.today - 2, slack=true, rerun=false)
    report = self.weekly_report_logs.find_by(date: date)
    msg = ""
    if report == nil || rerun
      record_instance_logs(rerun)
      usage = get_overall_usage((date == Date.today - 2 ? Date.today : date), true)

      start_date = Date.parse(self.start_date)
      if date < start_date
        puts "Given date is before the project start date"
        return
      end
      start_date = start_date > date.beginning_of_month ? start_date : date.beginning_of_month
      costs_this_month = api_query_cost(start_date, date)
      total_costs = begin
                     costs_this_month.map { |c| c['properties']['cost'] }.reduce(:+)
                   rescue NoMethodError
                     0.0
                   end
      total_costs = (total_costs * 10 * 1.25).ceil

      compute_nodes = self.instance_logs.where(compute: 1).where('timestamp LIKE ?', "%#{start_date.to_s[0..6]}%")
      compute_costs_this_month = costs_this_month.select { |cd| compute_nodes.any? { |node| node.instance_name == cd['properties']['resourceName'] } }
      compute_costs = begin
                     compute_costs_this_month.map { |c| c['properties']['cost'] }.reduce(:+)
                   rescue NoMethodError
                     0.0
                   end
      compute_costs = (compute_costs * 10 * 1.25).ceil
      
      remaining_budget = self.budget - total_costs
      logs = self.instance_logs.where('timestamp LIKE ?', "%#{date == Date.today - 2 ? Date.today : date}%").where(compute: 1)
      instances_date = logs.first ? Time.parse(logs.first.timestamp) : date + 0.5
      date_range = "1 - #{(date).day} #{Date::MONTHNAMES[date.month]}"
      date_warning = date > Date.today - 2 ? "\nWarning: AWS data takes roughly 48 hours to update, so these figures may be inaccurate\n" : nil

      msg = [
      "#{date_warning if date_warning}",
      ":calendar: \t\t\t\t Weekly Report for #{self.name} \t\t\t\t :calendar:",
      "*Monthly Budget:* #{self.budget} compute units",
      "*Compute Costs for #{date_range}:* #{compute_costs} compute units",
      "*Total Costs for #{date_range}:* #{total_costs} compute units",
      "*Remaining Monthly Budget:* #{remaining_budget} compute units\n",
      "*Current Usage (as of #{instances_date.strftime('%H:%M %Y-%m-%d')})*",
      "Currently, the cluster compute nodes are:",
      "`#{usage}`\n",
      ]

      msg = msg.join("\n") + "\n"

      if report && rerun
        report.update(content: msg, timestamp: Time.now)
        report.save!
      else
        WeeklyReportLog.create(project_id: self.id, content: msg, date: date, timestamp: Time.now)
      end
    else
      msg = "\t\t\t\t\t*Cached Report*\n" << report.content
    end
    send_slack_message(msg) if slack
    puts (msg.gsub(":calendar:", "").gsub("*", "").gsub(":awooga:", ""))
    puts '_' * 50
  end

  def record_instance_logs(rerun=false)
    today_logs = self.instance_logs.where('timestamp LIKE ?', "%#{Date.today}%")
    today_logs.delete_all if rerun
    if !today_logs.any?
      active_nodes = api_query_active_nodes
      active_nodes&.each do |node|
        name = node['id'].match(/virtualMachines\/(.*)\/providers/i)[1]
        cnode = today_compute_nodes.detect do |compute_node|
                  compute_node['name'] == name
                end
        type = cnode['properties']['hardwareProfile']['vmSize']
        compute = cnode.key?('tags') && cnode['tags']['type'] == 'compute'
        InstanceLog.create(
          instance_id: node['id'],
          project_id: id,
          instance_type: type,
          instance_name: name,
          compute: compute ? 1 : 0,
          status: node['properties']['availabilityState'],
          host: 'Azure',
          timestamp: Time.now.to_s
        )
      end
    end
  end

  def get_overall_usage(date, customer_facing=false)
    logs = self.instance_logs.where('timestamp LIKE ?', "%#{date}%").where(compute: 1)

    instance_counts = {}
    logs.each do |log|
      type = customer_facing ? log.customer_facing_type : log.instance_type
      if !instance_counts.has_key?(type)
        instance_counts[type] = {log.status => 1, "total" => 1}
      else
        if !instance_counts[type].has_key?(log.status)
          instance_counts[type][log.status] = 1
        else
          instance_counts[type][log.status] = instance_counts[type][log.status] + 1
        end
        instance_counts[type]['total'] = instance_counts[type]['total'] + 1
      end
    end

    overall_usage = ""
    instance_counts.each do |type|
      overall_usage << "#{type[1]["total"]} "
      overall_usage << "x #{type[0]}"
      overall_usage << "(#{type[1]["Unavailable"]} stopped)" if type[1]['Unavailable'] != nil
      overall_usage << " "
    end
    overall_usage == "" ? "None recorded" : overall_usage.strip
  end


  def api_query_compute_nodes
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines"
    query = {
      'api-version': '2020-06-01',
    }
    response = HTTParty.get(
      uri,
      query: query,
      headers: { 'Authorization': "Bearer #{bearer_token}" }
    )

    if response.success?
      vms = response['value']
      vms.select { |vm| vm.key?('tags') && vm['tags']['type'] == 'compute' }
    else
      puts "Error querying compute nodes for project #{name}/#{resource_group}. Error code #{response.code}."
    end
  end

  def api_query_cost(start_date, end_date=start_date)
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Consumption/usageDetails"
    query = {
      'api-version': '2019-10-01',
      '$filter': "properties/usageStart eq '#{start_date.to_s}' and properties/usageEnd eq '#{end_date.to_s}' and properties/resourceGroup eq '#{resource_group}'"
    }
    response = HTTParty.get(
      uri,
      query: query,
      headers: { 'Authorization': "Bearer #{bearer_token}" }
    )

    if response.success?
      details = response['value']
    else
      puts "Error querying daily cost Azure API for project #{name}/#{resource_group}. Error code #{response.code}."
    end
  end

  def api_query_active_nodes
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/providers/Microsoft.ResourceHealth/availabilityStatuses"
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
      nodes = response['value']
      nodes.select do |node|
        today_compute_nodes.any? do |cn|
          node['id'].match(/virtualMachines\/(.*)\/providers/i)[1] == cn['name']
        end
      end
    else
      puts "Error querying node status Azure API for project #{name}/#{resource_group}. Error code #{response.code}."
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

  def refresh_auth_token
    # refresh authorization token if necessary
    # tokens last for 3600 seconds (one hour)
    if Time.now.to_i > bearer_expiry.to_i
      update_bearer_token
    end
  end

  def construct_metadata
    @metadata = JSON.parse(metadata)
  end

end
