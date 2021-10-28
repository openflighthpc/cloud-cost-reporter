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
  MAX_API_ATTEMPTS = 3
  DEFAULT_TIMEOUT = 180
  @@prices = {}
  @@region_mappings = {}
  validates :filter_level,
    presence: true,
    inclusion: {
      in: ["resource group", "subscription"],
      message: "%{value} is not a valid filter level. Must be resource group or subscription."
    }

  after_initialize :construct_metadata
  after_initialize :update_region_mappings

  default_scope { where(host: "azure") }

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

  def resource_groups
    @metadata['resource_groups'] if self.filter_level == 'resource group'
  end

  def describe_resource_groups
    resource_groups.join(", ") if self.filter_level == 'resource group'
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

  def daily_report(date=DEFAULT_DATE, slack=true, text=true, rerun=false, verbose=false, customer_facing=false, short=false)
    @verbose = verbose
    refresh_auth_token
    record_instance_logs(rerun) if date == DEFAULT_DATE
    total_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "total")
    data_out_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "data_out")
    data_out_amount_log = self.usage_logs.find_by(start_date: date.to_s, description: "data_out")
    compute_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "compute")

    cached = total_cost_log && !rerun
    response = nil

    if rerun || !(total_cost_log && data_out_cost_log && data_out_amount_log && compute_cost_log)
      response = api_query_cost(date)
      total_cost_log = get_total_costs(response, date, rerun)
      data_out_cost_log, data_out_amount_log = get_data_out_figures(response, date, rerun)
      compute_cost_log = get_compute_costs(response, date, rerun)
      core_cost_log = get_core_costs(response, date, rerun)
      storage_cost_log = get_storage_costs(response, date, rerun)
    end

    overall_usage = get_overall_usage(date, customer_facing)

    msg = [
        "#{"*Cached report*" if cached}",
        ":moneybag: Usage for *#{self.name}* on #{date.to_s} :moneybag:",
        "*Compute Costs (GBP):* #{compute_cost_log.cost.to_f.ceil(2)}",
        ("*Compute Units (Flat):* #{compute_cost_log.compute_cost}" if !short),
        ("*Compute Units (Risk):* #{compute_cost_log.risk_cost}\n" if !short),
        ("*Data Out (GB):* #{data_out_amount_log.amount.to_f.ceil(4)}" if !short),
        "*Data Out Costs (GBP):* #{data_out_cost_log.cost.to_f.ceil(2)}",
        ("*Compute Units (Flat):* #{data_out_cost_log.compute_cost}" if !short),
        ("*Compute Units (Risk):* #{data_out_cost_log.risk_cost}\n" if !short),
        "*Total Costs (GBP):* #{total_cost_log.cost.to_f.ceil(2)}",
        "*Total Compute Units (Flat):* #{total_cost_log.compute_cost}",
        "*Total Compute Units (Risk):* #{total_cost_log.risk_cost}",
        "#{"\n" if !short}*FC Credits:* #{total_cost_log.fc_credits_cost}",
        ("*Compute Instance Usage:* #{overall_usage}" if !short)
      ].compact.join("\n") + "\n"
    send_slack_message(msg) if slack
    
    if text
      puts msg.gsub(":moneybag:", "").gsub("*", "")
      puts "_" * 50
    end
  end

  def weekly_report(date=DEFAULT_DATE, slack=true, text=true, rerun=false, verbose=false, customer_facing=true)
    @verbose = verbose
    refresh_auth_token
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
      total_costs = (total_costs * 12.5 * 1.25).ceil

      data_out_costs = costs_this_month.select { |cost| cost["properties"]["meterDetails"]["meterName"] == "Data Transfer Out" }

      data_out_cost = 0.0
      data_out_amount = 0.0
      data_out_costs.each do |cost|
        data_out_cost += cost['properties']['cost']
        data_out_amount += cost['properties']['quantity']
      end
      data_out_cost = (data_out_cost * 12.5 * 1.25).ceil

      compute_costs_this_month = costs_this_month.select do |cost|
        cost["tags"] && cost["tags"]["type"] == "compute" &&
        cost["properties"]["meterDetails"]["meterCategory"] == "Virtual Machines"
      end
      compute_costs = begin
                     compute_costs_this_month.map { |c| c['properties']['cost'] }.reduce(:+)
                   rescue NoMethodError
                     0.0
                   end
      compute_costs ||= 0.0
      compute_costs = (compute_costs * 12.5 * 1.25).ceil

      latest_logs = self.instance_logs.where('timestamp LIKE ?', "%#{date == DEFAULT_DATE ? Date.today : date}%").where(compute: 1)
      instances_date = latest_logs.first ? Time.parse(latest_logs.first.timestamp) : (date == DEFAULT_DATE ? Time.now : date + 0.5)
      update_prices

      inbetween_costs = 0.0
      inbetween_dates = ((date + 1.day)...instances_date.to_date).to_a
      inbetween_dates.each do |date|
        self.instance_logs.where('timestamp LIKE ?', "%#{date}%").where(compute: 1).each do |log|
          if log.status.downcase == "available"
            type = log.instance_type.gsub("Standard_", "").gsub("_", " ")
            inbetween_costs += @@prices[@@region_mappings[log.region]][type][0]
          end
        end
      end
      inbetween_costs = (inbetween_costs * 24 * 12.5 * 1.25).ceil
      inbetween_costs = (inbetween_costs + (fixed_daily_cu_cost * inbetween_dates.count)).ceil

      future_costs = 0.0
      latest_logs.each do |log|
        if log.status.downcase == 'available'
          type = log.instance_type.gsub("Standard_", "").gsub("_", " ")
          future_costs += @@prices[@@region_mappings[log.region]][type][0]
        end
      end
      daily_future_cu = (future_costs * 24 * 12.5 * 1.25).ceil
      total_future_cu = (daily_future_cu + fixed_daily_cu_cost).ceil

      remaining_budget = current_budget.to_i - total_costs
      remaining_days = (remaining_budget - inbetween_costs) / (daily_future_cu + fixed_daily_cu_cost)
      time_lag = (instances_date.to_date - date).to_i
      enough = (date + remaining_days) >= (date >> 1).beginning_of_month
      date_range = "1 - #{(date).day} #{Date::MONTHNAMES[date.month]}"
      date_warning = date > Date.today - 3 ? "\nWarning: data takes roughly 72 hours to update, so these figures may be inaccurate\n" : nil

      msg = [
      "#{date_warning if date_warning}",
      ":calendar: \t\t\t\t Weekly Report for #{self.name} \t\t\t\t :calendar:",
      "*Monthly Budget:* #{current_budget} compute units",
      "*Compute Costs for #{date_range}:* #{compute_costs} compute units",
      "*Data Egress Costs for #{date_range}:* #{data_out_cost} compute units (#{data_out_amount.ceil(2)} GB)",
      "*Total Costs for #{date_range}:* #{total_costs} compute units",
      "*Remaining Monthly Budget:* #{remaining_budget} compute units\n",
      "*Current Usage (as of #{instances_date.strftime('%H:%M %Y-%m-%d')})*",
      "Currently, the cluster compute nodes are:",
      "`#{usage}`\n",
      "The average cost for these compute nodes, in the above state, is about *#{daily_future_cu}* compute units per day.",
      "Other, fixed cluster costs are on average *#{fixed_daily_cu_cost}* compute units per day.\n",
      "The total estimated requirement is therefore *#{total_future_cu}* compute units per day, from today.\n",
      "*Predicted Usage*"
      ]

      if remaining_budget < 0
        msg << ":awooga:The monthly budget *has been exceeded*:awooga:."
      end
      if time_lag > 0
        msg << "Estimated total combined costs for the previous #{inbetween_dates.count} days are *#{inbetween_costs}* compute units, based on instances running on those days.\n"
      end
      if remaining_budget > 0
        msg << "Based on #{'this and ' if time_lag > 0 }the current usage, the remaining budget will be used up in *#{remaining_days}* days."
        msg << "The budget is predicted to therefore be *#{enough ? "sufficient" : ":awooga:insufficient:awooga:"}* for the rest of the month."
      end
      if remaining_budget < 0 || !enough
        excess = remaining_budget - (total_future_cu * (date.end_of_month.day - date.day))
         msg << "Based on #{'this and ' if time_lag > 0 && remaining_budget < 0}the current usage the budget will be exceeded by *#{excess}* compute units at the end of the month."
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
    return if self.end_date # can't record instance logs if cluster is no more

    refresh_auth_token
    today_logs = self.instance_logs.where('timestamp LIKE ?', "%#{Date.today}%")
    today_logs.delete_all if rerun
    if !today_logs.any?
      active_nodes = api_query_active_nodes
      active_nodes&.each do |node|
        # Azure API returns ids with inconsistent capitalisations so need to edit them here
        instance_id = node['id']
        instance_id.gsub!("resourcegroups", "resourceGroups")
        instance_id.gsub!("microsoft.compute/virtualmachines", "Microsoft.Compute/virtualMachines")
        instance_id_breakdown = instance_id.split("/")
        resource_group = instance_id_breakdown[4].downcase # sometimes Azure gives it uppercase, sometime lowercase
        instance_id_breakdown[4] = resource_group
        instance_id = instance_id_breakdown.join("/")
 
        name = node['id'].match(/virtualMachines\/(.*)\/providers/i)[1]
        region = node['location']
        cnode = today_compute_nodes.detect do |compute_node|
                  compute_node['name'] == name  && resource_group == compute_node['id'].split("/")[4].downcase
                end
        next if !cnode

        type = cnode['properties']['hardwareProfile']['vmSize']
        compute = cnode.key?('tags') && cnode['tags']['type'] == 'compute'
        compute_group = cnode.key?('tags') ? cnode['tags']['compute_group'] : nil
        InstanceLog.create(
          instance_id: instance_id,
          project_id: id,
          instance_type: type,
          instance_name: name,
          compute: compute ? 1 : 0,
          compute_group: compute_group,
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

  def get_total_costs(cost_entries, date, rerun)
    total_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "total")
    if !total_cost_log || rerun
      # the query has multiple values that sound useful (effectivePrice, cost, 
      # quantity, unitPrice). 'cost' is the value that is used on the Azure Portal
      # Cost Analysis page (under 'Actual Cost') for the period selected.
      daily_cost = begin
                    cost_entries.map { |c| c['properties']['cost'] }.reduce(:+)
                  rescue NoMethodError
                    0.0
                  end
      daily_cost ||= 0.0

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
    end
    total_cost_log
  end

  # This is just the cost for running the compute VMs, does not include costs related to associated storage or data out costs.
  def get_compute_costs(cost_entries, date, rerun)
    compute_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "compute")

    if !compute_cost_log || rerun
      compute_costs = cost_entries.select do |cost|
        cost["tags"] && cost["tags"]["type"] == "compute" &&
        cost["properties"]["meterDetails"]["meterCategory"] == "Virtual Machines"
      end

      cost_breakdown = {total: 0.0}
      compute_costs.each do |cost|
        value = cost['properties']['cost']
        group = cost["tags"] ? cost["tags"]["compute_group"] : nil
        cost_breakdown[:total] += value
        if group && !cost_breakdown.has_key?(group)
          cost_breakdown[group] = value
        elsif group
          cost_breakdown[group] += value
        end
      end
      
      cost_breakdown.each do |key, value|
        scope = key == :total ? "compute" : key
        log = self.cost_logs.find_by(date: date.to_s, scope: scope)
        if log && rerun
          log.assign_attributes(cost: cost_breakdown[key], timestamp: Time.now.to_s)
          log.save!
        elsif !log
          log = CostLog.create(
            project_id: id,
            cost: value,
            currency: 'GBP',
            scope: scope,
            date: date.to_s,
            timestamp: Time.now.to_s
          )
        end
        compute_cost_log = log if key == :total
      end
    end
    compute_cost_log
  end

  # This includes any resources tagged as core. Does not include disk or data out costs.
  def get_core_costs(cost_entries, date, rerun)
    core_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "core")

    if !core_cost_log || rerun
      core_costs = cost_entries.select do |cost|
        cost["tags"] && cost["tags"]["type"] == "core" &&
        cost["properties"]["meterDetails"]["meterName"] != "Data Transfer Out" && 
        !cost["properties"]["meterDetails"]["meterName"].include?("Disks")
      end  
      core_cost = begin
                      core_costs.map { |c| c['properties']['cost'] }.reduce(:+)
                     rescue NoMethodError
                      0.0
                     end
      core_cost ||= 0.0
      if rerun && core_cost_log
        core_cost_log.assign_attributes(cost: core_cost, timestamp: Time.now.to_s)
        core_cost_log.save!
      else
        core_cost_log = CostLog.create(
          project_id: id,
          cost: core_cost,
          currency: 'GBP',
          scope: 'core',
          date: date.to_s,
          timestamp: Time.now.to_s
        )
      end
    end
    core_cost_log
  end

  def get_data_out_figures(cost_entries, date, rerun)
    data_out_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "data_out")
    data_out_amount_log = self.usage_logs.find_by(start_date: date.to_s, description: "data_out")
    data_out_figures = nil
    # only calculate if don't already have data in logs, or asked to recalculate
    if !data_out_cost_log || !data_out_amount_log || rerun
      data_out_costs = cost_entries.select { |cost| cost["properties"]["meterDetails"]["meterName"] == "Data Transfer Out" }

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

  def get_storage_costs(cost_entries, date, rerun)
    storage_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "storage")

    if !storage_cost_log || rerun
      storage_costs = cost_entries.select { |cost| cost["properties"]["meterDetails"]["meterName"].include?("Disks") }
      storage_cost = begin
                      storage_costs.map { |c| c['properties']['cost'] }.reduce(:+)
                     rescue NoMethodError
                      0.0
                     end
      storage_cost ||= 0.0
      if rerun && storage_cost_log
        storage_cost_log.assign_attributes(cost: storage_cost, timestamp: Time.now.to_s)
        storage_cost_log.save!
      else
        storage_cost_log = CostLog.create(
          project_id: id,
          cost: storage_cost,
          currency: 'GBP',
          scope: 'storage',
          date: date.to_s,
          timestamp: Time.now.to_s
        )
      end
    end
    storage_cost_log
  end

  def record_logs_for_range(start_date, end_date, rerun=false)
    update_bearer_token
    record_instance_logs # need some instance logs in order to determine compute costs
    (start_date..end_date).to_a.each do |date|
      logs = self.cost_logs.where(date: date)
      if !logs.any? || rerun
        response = api_query_cost(date)
        get_total_costs(response, date, rerun)
        get_compute_costs(response, date, rerun)
        get_data_out_figures(response, date, rerun)
        get_core_costs(response, date, rerun)
        get_storage_costs(response, date, rerun)
      end
    end
  end

  def api_query_compute_nodes
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Compute/virtualMachines"
    query = {
      'api-version': '2020-06-01',
    }
    attempt = 0
    error = AzureApiError.new("Timeout error querying compute nodes for project"\
                              "#{name}. All #{MAX_API_ATTEMPTS} attempts timed out.")
    begin
      attempt += 1
      response = HTTParty.get(
        uri,
        query: query,
        headers: { 'Authorization': "Bearer #{bearer_token}" },
        timeout: DEFAULT_TIMEOUT
      )

      if response.success?
        vms = response['value']
        vms.select { |vm| vm.key?('tags') && vm['tags']['type'] == 'compute' && (filter_level == "subscription" ||
        (filter_level == "resource group" && self.resource_groups.include?(vm['id'].split('/')[4].downcase))) }
      elsif response.code == 504
        raise Net::ReadTimeout
      else
        raise AzureApiError.new("Error querying compute nodes for project #{name}."\
                                "\nError code #{response.code}.\n#{response if @verbose}")
      end
    rescue Net::ReadTimeout
      msg = "Attempt #{attempt}: Request timed out.\n"
      if response
        msg << "Error code #{response.code}.\n#{response if @verbose}\n"
      end
      error.error_messages.append(msg)
      if attempt < MAX_API_ATTEMPTS
        retry
      else
        raise error
      end
    end 
  end

  def api_query_cost(start_date, end_date=start_date)
    resource_groups_conditional = ""
    if filter_level == "resource group"
      self.resource_groups.each_with_index do |group, index|
        if index == 0 
          resource_groups_conditional << "and properties/resourceGroup eq '#{group}'"
        else
          resource_groups_conditional << " or properties/resourceGroup eq '#{group}'"
        end
      end
    end
    filter = "properties/usageStart ge '#{start_date.to_s}' and properties/usageEnd le '#{end_date.to_s}'"
    filter << " #{resource_groups_conditional}" if filter_level == "resource group"
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Consumption/usageDetails?$expand=meterDetails"
    query = {
      'api-version': '2019-10-01',
      '$filter': filter
    }
    attempt = 0
    error = AzureApiError.new("Timeout error querying daily cost Azure API for project"\
                              " #{name}. All #{MAX_API_ATTEMPTS} attempts timed out.")
    begin
      attempt += 1
      response = HTTParty.get(
        uri,
        query: query,
        headers: { 'Authorization': "Bearer #{bearer_token}" },
        timeout: DEFAULT_TIMEOUT
      )
      if response.success?
        details = response['value']
        # Sometimes Azure will duplicate cost items, or have cost items with the same name/id but different
        # details. We will remove the full duplicates and keep those with the same name/id but different details.
        # We assume there is no more than 1 duplicate for each
        if details.length > 1
          details.sort_by! { |cost| [cost["name"], cost['properties']['cost']] }
          previous = nil
          filtered_details = details.reject.with_index do |cost, index|
            result = false
            if index > 0
              result = cost == previous
            end
            previous = cost
            result
          end
        end
        filtered_details ? filtered_details : details
      elsif response.code == 504
        raise Net::ReadTimeout
      else
        raise AzureApiError.new("Error querying daily cost Azure API for project #{name}.\nError code #{response.code}.\n#{response if @verbose}")
      end
    rescue Net::ReadTimeout
      msg = "Attempt #{attempt}: Request timed out.\n"
      if response
        msg << "Error code #{response.code}.\n#{response if @verbose}\n"
      end
      error.error_messages.append(msg)
      if attempt < MAX_API_ATTEMPTS
        retry
      else
        raise error
      end
    end 
  end

  def api_query_active_nodes
    uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.ResourceHealth/availabilityStatuses"
    query = {
      'api-version': '2020-05-01',
    }
    attempt = 0
    error = AzureApiError.new("Timeout error querying node status Azpire API for project #{name}."\
                              "All #{MAX_API_ATTEMPTS} attempts timed out.")
    begin
      attempt += 1 
      response = HTTParty.get(
        uri,
        query: query,
        headers: { 'Authorization': "Bearer #{bearer_token}" },
        timeout: DEFAULT_TIMEOUT
      )
      if response.success?
        nodes = response['value']
        nodes.select do |node|
          next if !node['id'].match(/virtualmachines/i)
          r_group = node['id'].split('/')[4].downcase
          if filter_level == "subscription" || (filter_level == "resource group" && self.resource_groups.include?(r_group))
            today_compute_nodes.any? do |cn|
              node['id'].match(/virtualMachines\/(.*)\/providers/i)[1] == cn['name']
            end
          end
        end
      elsif response.code == 504
        raise Net::ReadTimeout
      else
        raise AzureApiError.new("Error querying node status Azure API for project #{name}.\nError code #{response.code}.\n#{response if @verbose}")
      end
    rescue Net::ReadTimeout
      msg = "Attempt #{attempt}: Request timed out.\n"
      if response
        msg << "Error code #{response.code}.\n#{response if @verbose}\n"
      end
      error.error_messages.append(msg)
      if attempt < MAX_API_ATTEMPTS
        retry
      else
        raise error
      end
    end
  end

  def update_bearer_token
    attempt = 0
    error = AzureApiError.new("Timeout error obtaining new authorization token for project"\
                              "#{name}. All #{MAX_API_ATTEMPTS} attempts timed out.")
    begin
      attempt += 1
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
        },
        timeout: DEFAULT_TIMEOUT
      )

      if response.success?
        body = JSON.parse(response.body)
        @metadata['bearer_token'] = body['access_token']
        @metadata['bearer_expiry'] = body['expires_on']
        self.metadata = @metadata.to_json
        self.save
      elsif response.code == 504
        raise Net::ReadTimeout
      else
        raise AzureApiError.new("Error obtaining new authorization token for project #{name}.\nError code #{response.code}\n#{response if @verbose}")
      end
    rescue Net::ReadTimeout
      msg = "Attempt #{attempt}: Request timed out.\n"
      if response
        msg << "Error code #{response.code}.\n#{response if @verbose}\n"
      end
      error.error_messages.append(msg)
      if attempt < MAX_API_ATTEMPTS
        retry
      else
        raise error
      end
    end
  end

  def get_prices
    regions = InstanceLog.where(host: "Azure").select(:region).distinct.pluck(:region) | ["uksouth"]
    regions.sort!

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
      refresh_auth_token
      uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Commerce/RateCard?api-version=2016-08-31-preview&$filter=OfferDurableId eq 'MS-AZR-0003P' and Currency eq 'GBP' and Locale eq 'en-GB' and RegionInfo eq 'GB'"
      attempt = 0
      error = AzureApiError.new("Timeout error obtaining latest Azure price list."\
                                "All #{MAX_API_ATTEMPTS} attempts timed out.")
      begin
        attempt += 1
        response = HTTParty.get(
          uri,
          headers: { 'Authorization': "Bearer #{bearer_token}" },
          timeout: DEFAULT_TIMEOUT
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
        elsif response.code == 504
          raise Net::ReadTimeout
        else
          raise AzureApiError.new("Error obtaining latest Azure price list. Error code #{response.code}.\n#{response if @verbose}")
        end
      rescue Net::ReadTimeout
        msg = "Attempt #{attempt}: Request timed out.\n"
        if response
          msg << "Error code #{response.code}.\n#{response if @verbose}\n"
        end
        error.error_messages.append(msg)
        if attempt < MAX_API_ATTEMPTS
          retry
        else
          raise error
        end
      end
    end
  end

  def get_instance_sizes
    regions = InstanceLog.where(host: "Azure").select(:region).distinct.pluck(:region) | ["uksouth"]
    regions.sort!

    timestamp = begin
      Date.parse(File.open('azure_instance_sizes.txt').first) 
    rescue ArgumentError, Errno::ENOENT
      false
    end
    existing_regions = begin
      File.open('azure_instance_sizes.txt').first(2).last.chomp
    rescue Errno::ENOENT 
      false
    end

    if timestamp == false || Date.today - timestamp >= 1 || existing_regions == false || existing_regions != regions.to_s
      refresh_auth_token
      uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Compute/skus?api-version=2019-04-01"
      attempt = 0
      error = AzureApiError.new("Timeout error obtaining latest Azure instance list."\
                                "All #{MAX_API_ATTEMPTS} attempts timed out.")
      begin
        attempt += 1
        response = HTTParty.get(
          uri,
          headers: { 'Authorization': "Bearer #{bearer_token}" },
          timeout: DEFAULT_TIMEOUT
        )
      
        if response.success?
          File.write('azure_instance_sizes.txt', "#{Time.now}\n")
          File.write('azure_instance_sizes.txt', "#{regions}\n", mode: "a")
          response["value"].each do |instance|
            if instance["resourceType"] == "virtualMachines" && regions.include?(instance["locations"][0]) &&
              instance["name"].include?("Standard")
              details = {
                instance_type: instance["name"], instance_family: instance["family"],
                location: instance["locations"][0],
                cpu: 0, gpu: 0, mem: 0
              }

              instance["capabilities"].each do |capability|
                if capability["name"] == "MemoryGB"
                  details[:mem] = capability["value"].to_f
                elsif capability["name"] == "vCPUs"
                  details[:cpu] = capability["value"].to_i
                elsif capability["name"] == "GPUs"
                  details[:gpu] = capability["value"].to_i
                end
              end
              File.write("azure_instance_sizes.txt", details.to_json, mode: "a")
              File.write("azure_instance_sizes.txt", "\n", mode: "a")
            end
          end
        elsif response.code == 504
          raise Net::ReadTimeout
        else
          raise AzureApiError.new("Error obtaining latest Azure instance list. Error code #{response.code}.\n#{response if @verbose}")
        end
      rescue Net::ReadTimeout
        msg = "Attempt #{attempt}: Request timed out.\n"
        if response
          msg << "Error code #{response.code}.\n#{response if @verbose}\n"
        end
        error.error_messages.append(msg)
        if attempt < MAX_API_ATTEMPTS
          retry
        else
          raise error
        end
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
  attr_accessor :error_messages
  def initialize(msg)
    @error_messages = []
    super(msg)
  end
end
