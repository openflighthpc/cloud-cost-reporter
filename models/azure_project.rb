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

require 'httparty'
require_relative 'project'

class AzureProject < Project
  @@prices = {}
  @@region_mappings = {}

  after_initialize :construct_metadata
  after_initialize :update_region_mappings

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

  def resource_groups
    @metadata['resource_groups']
  end

  def describe_resource_groups
    resource_groups.join(", ")
  end

  def validate_credentials
    puts "Validating Azure project credentials. This may take some time (2-3 mins).\n\n"
    valid = true
    @verbose = true
    begin
      update_bearer_token
    rescue => error
      valid = false
      puts "#{error}\n\n"
    end

    begin
      api_query_active_nodes
    rescue => error
      valid = false
      puts "#{error}\n\n"
    end
    
    begin
      api_query_cost(Date.today.to_s)
    rescue => error
      valid = false
      puts "#{error}\n\n"
    end

    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Commerce/RateCard?api-version=2016-08-31-preview&$filter=OfferDurableId eq 'MS-AZR-0003P' and Currency eq 'GBP' and Locale eq 'en-GB' and RegionInfo eq 'GB'"
    response = HTTParty.get(
      uri,
      headers: { 'Authorization': "Bearer #{bearer_token}" }
      )

    if !response.success?
      valid = false
      puts "Unable to connect to Azure Pricing: #{response}\n\n"
    end

    if valid
      puts "Credentials valid for project #{self.name}."
    else
      puts "Please double check your credentials and permissions."
    end
    valid
  end

  def daily_report(date=DEFAULT_DATE, slack=true, text=true, rerun=false, verbose=false, customer_facing=false)
    @verbose = verbose
    update_bearer_token
    record_instance_logs(rerun) if date == DEFAULT_DATE
    total_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "total")
    data_out_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "data_out")
    data_out_amount_log = self.usage_logs.find_by(start_date: date.to_s, description: "data_out")
    compute_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "compute")

    cached = total_cost_log && !rerun
    response = nil

    if rerun || !(total_cost_log && data_out_cost_log && data_out_amount_log && compute_cost_log)
      response = api_query_cost(date)
      # the query has multiple values that sound useful (effectivePrice, cost, 
      # quantity, unitPrice). 'cost' is the value that is used on the Azure Portal
      # Cost Analysis page (under 'Actual Cost') for the period selected.
      daily_cost = begin
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

      data_out_cost_log, data_out_amount_log = get_data_out_figures(response, date, rerun)
      compute_cost_log = get_compute_costs(response, date, rerun)
    end

    overall_usage = get_overall_usage(date, customer_facing)

    msg = [
        "#{"*Cached report*" if cached}",
        ":moneybag: Usage for #{date.to_s} :moneybag:",
        "*Compute Cost (GBP):* #{compute_cost_log.cost.to_f.ceil(2)}",
        "*Compute Units (Flat):* #{compute_cost_log.compute_cost}",
        "*Compute Units (Risk):* #{compute_cost_log.risk_cost}\n",
        "*Data Out (GB):* #{data_out_amount_log.amount.to_f.ceil(4)}",
        "*Data Out Costs (GBP):* #{data_out_cost_log.cost.to_f.ceil(2)}",
        "*Compute Units (Flat):* #{data_out_cost_log.compute_cost}",
        "*Compute Units (Risk):* #{data_out_cost_log.risk_cost}\n",
        "*Total Cost (GBP):* #{total_cost_log.cost.to_f.ceil(2)}",
        "*Total Compute Units (Flat):* #{total_cost_log.compute_cost}",
        "*Total Compute Units (Risk):* #{total_cost_log.risk_cost}\n",
        "*FC Credits:* #{total_cost_log.fc_credits_cost}",
        "*Compute Instance Usage:* #{overall_usage}"
      ].join("\n") + "\n"
    send_slack_message(msg) if slack
    
    if text
      puts "\nProject: #{self.name}\n"
      puts msg.gsub(":moneybag:", "").gsub("*", "")
      puts "_" * 50
    end
  end

  def weekly_report(date=DEFAULT_DATE, slack=true, text=true, rerun=false, verbose=false, customer_facing=true)
    @verbose = verbose
    update_bearer_token
    report = self.weekly_report_logs.find_by(date: date)
    msg = ""
    if report == nil || rerun
      record_instance_logs(rerun)
      usage = get_overall_usage((date == DEFAULT_DATE ? Date.today : date), customer_facing)

      start_date = Date.parse(self.start_date)
      if date < start_date
        puts "Given date is before the project start date"
        return
      elsif date > Date.today
        puts "Given date is in the future"
        return
      end
      start_date = start_date > date.beginning_of_month ? start_date : date.beginning_of_month
      costs_this_month = api_query_cost(start_date, date)
      total_costs = begin
                     costs_this_month.map { |c| c['properties']['cost'] }.reduce(:+)
                   rescue NoMethodError
                     0.0
                   end
      total_costs ||= 0.0
      total_costs = (total_costs * 10 * 1.25).ceil

      data_out_costs = costs_this_month.select do |cost|
        cost['properties']["additionalInfo"] &&
        JSON.parse(cost["properties"]["additionalInfo"])["UsageResourceKind"]&.include?("DataTrOut")
      end

      data_out_cost = 0.0
      data_out_amount = 0.0
      data_out_costs.each do |cost|
        data_out_cost += cost['properties']['cost']
        data_out_amount += cost['properties']['quantity']
      end
      data_out_cost = (data_out_cost * 10 * 1.25).ceil

      compute_nodes = self.instance_logs.where(compute: 1).where('timestamp LIKE ?', "%#{start_date.to_s[0..6]}%")
      compute_costs_this_month = costs_this_month.select { |cd| compute_nodes.any? { |node| node.instance_name == cd['properties']['resourceName'] } }
      compute_costs = begin
                     compute_costs_this_month.map { |c| c['properties']['cost'] }.reduce(:+)
                   rescue NoMethodError
                     0.0
                   end
      compute_costs ||= 0.0
      compute_costs = (compute_costs * 10 * 1.25).ceil

      logs = self.instance_logs.where('timestamp LIKE ?', "%#{date == DEFAULT_DATE ? Date.today : date}%").where(compute: 1)
      update_prices
      future_costs = 0.0
      logs.each do |log|
        if log.status.downcase == 'available'
          type = log.instance_type.gsub("Standard_", "").gsub("_", " ")
          future_costs += @@prices[@@region_mappings[log.region]][type][0]
        end
      end
      daily_future_cu = (future_costs * 24 * 10 * 1.25).ceil
      total_future_cu = (daily_future_cu + fixed_daily_cu_cost).ceil

      remaining_budget = self.budget.to_i - total_costs
      remaining_days = remaining_budget / (daily_future_cu + fixed_daily_cu_cost)
      instances_date = logs.first ? Time.parse(logs.first.timestamp) : (date == DEFAULT_DATE ? Time.now : date + 0.5)
      time_lag = (instances_date.to_date - date).to_i
      enough = (date + remaining_days + time_lag) >= (date >> 1).beginning_of_month
      date_range = "1 - #{(date).day} #{Date::MONTHNAMES[date.month]}"
      date_warning = date > Date.today - 3 ? "\nWarning: data takes roughly 72 hours to update, so these figures may be inaccurate\n" : nil

      msg = [
      "#{date_warning if date_warning}",
      ":calendar: \t\t\t\t Weekly Report for #{self.name} \t\t\t\t :calendar:",
      "*Monthly Budget:* #{self.budget} compute units",
      "*Compute Costs for #{date_range}:* #{compute_costs} compute units",
      "*Data Egress Costs for #{date_range}:* #{data_out_cost} compute units (#{data_out_amount.ceil(2)} GB)",
      "*Total Costs for #{date_range}:* #{total_costs} compute units",
      "*Remaining Monthly Budget:* #{remaining_budget} compute units\n",
      "*Current Usage (as of #{instances_date.strftime('%H:%M %Y-%m-%d')})*",
      "Currently, the cluster compute nodes are:",
      "`#{usage}`\n",
      "The average cost for these compute nodes, in the above state, is about *#{daily_future_cu}* compute units per day.",
      "Other, fixed cluster costs are on average *#{fixed_daily_cu_cost}* compute units per day.\n",
      "The total estimated requirement is therefore *#{total_future_cu}* compute units per day.\n",
      "*Predicted Usage*"
      ]

      if remaining_budget < 0
        msg << ":awooga:The monthly budget *has been exceeded*:awooga:."
      else
        msg << "Based on the current usage, the remaining budget will be used up in *#{remaining_days}* days."
        msg << "#{time_lag > 0 ? "As tracking is *#{time_lag}* days behind, t" : "T"}he budget is predicted to therefore be *#{enough ? "sufficient" : ":awooga:insufficient:awooga:"}* for the rest of the month."
      end
      if remaining_budget < 0 || !enough
        excess = remaining_budget - (total_future_cu * (date.end_of_month.day - date.day))
        msg << "Based on current usage the budget will be exceeded by *#{excess}* compute units at the end of the month."
      end
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
    if text
      puts (msg.gsub(":calendar:", "").gsub("*", "").gsub(":awooga:", ""))
      puts '_' * 50
    end
  end

  def record_instance_logs(rerun=false)
    today_logs = self.instance_logs.where('timestamp LIKE ?', "%#{Date.today}%")
    today_logs.delete_all if rerun
    if !today_logs.any?
      active_nodes = api_query_active_nodes
      active_nodes&.each do |node|
        name = node['id'].match(/virtualMachines\/(.*)\/providers/i)[1]
        region = node['location']
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
          region: region,
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

  def get_compute_costs(cost_entries, date, rerun)
    compute_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "compute")

    if !compute_cost_log
      compute_costs = cost_entries.select { |cd| historic_compute_nodes(date).any? { |node| node.instance_name == cd['properties']['resourceName'] } }
      compute_cost = begin
                      compute_costs.map { |c| c['properties']['cost'] }.reduce(:+)
                     rescue NoMethodError
                      0.0
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
    compute_cost_log
  end

  def get_data_out_figures(cost_entries, date, rerun)
    data_out_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "data_out")
    data_out_amount_log = self.usage_logs.find_by(start_date: date.to_s, description: "data_out")
    data_out_figures = nil
    # only make query if don't already have data in logs or asked to recalculate
    if !data_out_cost_log || !data_out_amount_log || rerun
      data_out_costs = cost_entries.select do |cost|
        cost['properties']["additionalInfo"] &&
        JSON.parse(cost["properties"]["additionalInfo"])["UsageResourceKind"]&.include?("DataTrOut")
      end

      data_out_cost = 0.0
      data_out_amount = 0.0
      data_out_costs.each do |cost|
        data_out_cost += cost['properties']['cost']
        data_out_amount += cost['properties']['quantity']
      end
      
      if data_out_cost_log && rerun
        data_out_cost_log.assign_attributes(cost: data_out_cost, timestamp: Time.now.to_s)
        data_out_cost_log.save!
      else
        data_out_cost_log = CostLog.create(
          project_id: self.id,
          cost: data_out_cost,
          currency: "GBP",
          date: date.to_s,
          scope: "data_out",
          timestamp: Time.now.to_s
        )
      end

      if data_out_amount_log && rerun
        data_out_amount_log.assign_attributes(amount: data_out_amount, timestamp: Time.now.to_s)
        data_out_amount_log.save!
      else
        data_out_amount_log = UsageLog.create(
          project_id: self.id,
          amount: data_out_amount,
          unit: "GB",
          start_date: date.to_s,
          end_date: (date + 1).to_s,
          description: "data_out",
          scope: "project",
          timestamp: Time.now.to_s
        )
      end
    end
    return data_out_cost_log, data_out_amount_log
  end

  def api_query_compute_nodes
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Compute/virtualMachines"
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
      vms.select { |vm| vm.key?('tags') && vm['tags']['type'] == 'compute' && self.resource_groups.include?(vm['id'].split('/')[4].downcase) }
    else
      raise AzureApiError.new("Error querying compute nodes for project #{name}.\nError code #{response.code}.\n#{response if @verbose}")
    end
  end

  def api_query_cost(start_date, end_date=start_date)
    resource_groups_conditional = ""
    self.resource_groups.each_with_index do |group, index|
      if index == 0 
        resource_groups_conditional << "and properties/resourceGroup eq '#{group}'"
      else
        resource_groups_conditional << " or properties/resourceGroup eq '#{group}'"
      end
    end
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Consumption/usageDetails"
    query = {
      'api-version': '2019-10-01',
      '$filter': "properties/usageStart ge '#{start_date.to_s}' and properties/usageEnd le '#{end_date.to_s}' #{resource_groups_conditional}"
    }
    response = HTTParty.get(
      uri,
      query: query,
      headers: { 'Authorization': "Bearer #{bearer_token}" }
    )
    if response.success?
      details = response['value']
    else
      raise AzureApiError.new("Error querying daily cost Azure API for project #{name}.\nError code #{response.code}.\n#{response if @verbose}")
    end
  end

  def api_query_active_nodes
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.ResourceHealth/availabilityStatuses"
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
        r_group = node['id'].split('/')[4].downcase
        if self.resource_groups.include?(r_group)
          today_compute_nodes.any? do |cn|
            node['id'].match(/virtualMachines\/(.*)\/providers/i)[1] == cn['name']
          end
        end
      end
    else
      raise AzureApiError.new("Error querying node status Azure API for project #{name}.\nError code #{response.code}.\n#{response if @verbose}")
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
      raise AzureApiError.new("Error obtaining new authorization token for project #{name}.\nError code #{response.code}\n#{response if @verbose}")
    end
  end

  def get_prices
    regions = InstanceLog.where(host: "Azure").select(:region).distinct.pluck(:region).sort
    regions.map! do |region|
      value = @@region_mappings[region]
      puts "No region mapping for #{region}, please update 'azure_region_names.txt' and rerun" and return if !value
      value
    end
    timestamp = begin
      Date.parse(File.open('azure_prices.txt').first) 
    rescue ArgumentError, Errno::ENOENT
      false
    end
    existing_regions = begin
      File.open('azure_prices.txt').first(2).last.chomp
    rescue Errno::ENOENT 
      false
    end
    if timestamp == false || Date.today - timestamp >= 1 || existing_regions == false || existing_regions != regions.to_s
      update_bearer_token
      uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Commerce/RateCard?api-version=2016-08-31-preview&$filter=OfferDurableId eq 'MS-AZR-0003P' and Currency eq 'GBP' and Locale eq 'en-GB' and RegionInfo eq 'GB'"
      response = HTTParty.get(
        uri,
        headers: { 'Authorization': "Bearer #{bearer_token}" }
      )

      if response.success?
        File.write('azure_prices.txt', "#{Time.now}\n")
        File.write('azure_prices.txt', "#{regions}\n", mode: "a")
        response['Meters'].each do |meter|
          if regions.include?(meter['MeterRegion']) && meter['MeterCategory'] == "Virtual Machines" &&
            !meter['MeterName'].downcase.include?('low priority') &&
            !meter["MeterSubCategory"].downcase.include?("windows")
            File.write("azure_prices.txt", meter.to_json, mode: "a")
            File.write("azure_prices.txt", "\n", mode: "a")
          end
        end
      else
        raise AzureApiError.new("Error obtaining latest Azure price list. Error code #{response.code}.\n#{response if @verbose}")
      end
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

  def update_prices
    if @@prices == {}
      get_prices
      File.open('azure_prices.txt').each_with_index do |entry, index|
        if index > 1
          entry = JSON.parse(entry)
          instance_type = entry['MeterName']
          region = entry['MeterRegion']
          if !@@prices.has_key?(region)
            @@prices[region] = {}
          end

          if !@@prices[region].has_key?(instance_type) ||
            (@@prices[region].has_key?(instance_type) &&
            Date.parse(entry['EffectiveDate']) > @@prices[region][instance_type][1])
            @@prices[region][instance_type] = [entry['MeterRates']["0"].to_f, Date.parse(entry['EffectiveDate'])]
          end
        end
      end
    end
  end

  def update_region_mappings
    if @@region_mappings == {}
      file = File.open('azure_region_names.txt')
      file.readlines.each do |line|
        line = line.split(",")
        @@region_mappings[line[0]] = line[1].strip
      end
    end
  end
end

class AzureApiError < StandardError
end
