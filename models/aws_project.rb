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

require 'aws-sdk-costexplorer'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-ec2'
require 'aws-sdk-pricing'
require_relative 'project'

class AwsProject < Project
  @@prices = {}
  @@region_mappings = {}
  validates :filter_level,
    presence: true,
    inclusion: {
      in: %w(tag account),
      message: "%{value} is not a valid filter level. Must be tag or account."
    }
  after_initialize :add_sdk_objects

  default_scope { where(host: "aws") }

  def access_key_ident
    @metadata['access_key_ident']
  end

  def key
    @metadata['key']
  end

  def regions
    @metadata['regions']
  end

  def describe_regions
    regions.join(", ")
  end

  def excluded_instances
    @excluded_instances ||= self.instance_logs.select {|i| !i.compute?}.map {|i| i.instance_id}.uniq
    # if given an empty array the relevant queries will fail, so instead provide a dummy instance.
    !@excluded_instances.any? ? ["abc"] : @excluded_instances
  end

  def add_sdk_objects
    @metadata = JSON.parse(self.metadata)
    Aws.config.update({region: "us-east-1"})
    @explorer = Aws::CostExplorer::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
    @pricing_checker = Aws::Pricing::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
    determine_region_mappings 
  end

  def determine_region_mappings
    if @@region_mappings == {}
      file = File.open('aws_region_names.txt')
      file.readlines.each do |line|
        line = line.split(",")
        @@region_mappings[line[0]] = line[1].strip
      end
    end
  end

  def validate_credentials
    puts "Validating AWS project credentials."
    valid = true
 
    begin
      @explorer = Aws::CostExplorer::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
      @instances_checker = Aws::EC2::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: self.regions.first)
      @pricing_checker = Aws::Pricing::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
    rescue Aws::Errors::MissingRegionError => error
      puts "Unable to create AWS SDK objects due to missing region: #{error}"
      return false
    end

    begin
      @explorer.get_cost_and_usage(compute_cost_query(DEFAULT_DATE))
    rescue  Aws::CostExplorer::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      valid = false
      puts "Unable to connect to AWS Cost Explorer: #{error}"
    end
    
    begin
      @instances_checker.describe_instances(project_instances_query)
    rescue Aws::EC2::Errors::ServiceError, Aws::Errors::MissingRegionError, Seahorse::Client::NetworkingError => error
      valid = false
      puts "Unable to connect to AWS EC2: #{error}."
    end

    begin
      @pricing_checker.get_products(service_code: "AmazonEC2", format_version: "aws_v1", max_results: 1)
    rescue Aws::Pricing::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      valid = false
      puts "Unable to connect to AWS Pricing: #{error}"
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
    start_date = Date.parse(self.start_date)
    if date < start_date
      puts "Given date is before the project start date"
      return
    elsif date > Date.today
      puts "Given date is in the future"
      return
    end

    record_instance_logs(rerun) if date == DEFAULT_DATE
    
    cached = !rerun && self.cost_logs.find_by(date: date.to_s, scope: "total")

    compute_cost_log = get_compute_costs(date, date + 1.day, rerun)
    core_cost_log = get_core_costs(date, date + 1.day, rerun)
    data_out_cost_log, data_out_amount_log = get_data_out_figures(date, date + 1.day, rerun)
    storage_cost_log = get_storage_costs(date, date + 1.day, rerun)
    total_cost_log = get_total_costs(date, date + 1.day, rerun)
    overall_usage = get_overall_usage(date, customer_facing)
    usage_breakdown = get_usage_hours_by_instance_type(date, rerun, customer_facing)

    date_warning = date > Date.today - 2 ? "\nWarning: AWS data takes roughly 48 hours to update, so these figures may be inaccurate\n" : nil

    msg = [
      "#{date_warning if date_warning}",
      "#{"*Cached report*" if cached}",
      ":moneybag: Usage for *#{self.name}* on #{date.to_s} :moneybag:",
      "*Compute Costs (USD):* #{compute_cost_log.cost.to_f.ceil(2)}",
      ("*Compute Units (Flat):* #{compute_cost_log.compute_cost}" if !short),
      ("*Compute Units (Risk):* #{compute_cost_log.risk_cost}\n" if !short),
      ("*Data Out (GB):* #{data_out_amount_log.amount.to_f.ceil(4)}" if !short),
      "*Data Out Costs (USD):* #{data_out_cost_log.cost.to_f.ceil(2)}",
      ("*Compute Units (Flat):* #{data_out_cost_log.compute_cost}" if !short),
      ("*Compute Units (Risk):* #{data_out_cost_log.risk_cost}\n" if !short),
      "*Total Costs (USD):* #{total_cost_log.cost.to_f.ceil(2)}",
      "*Total Compute Units (Flat):* #{total_cost_log.compute_cost}",
      "*Total Compute Units (Risk):* #{total_cost_log.risk_cost}",
      "#{"\n" if !short}*FC Credits:* #{total_cost_log.fc_credits_cost}",
      ("*Compute Instance Usage:* #{overall_usage.strip}" if !short),
      ("*Compute Instance Hours:* #{usage_breakdown}" if !short)
    ].compact.join("\n") + "\n"

    send_slack_message(msg) if slack

    if text
      puts msg.gsub(":moneybag:", "").gsub("*", "").gsub("\t", "")
      puts "_" * 50
    end
  end

  def weekly_report(date=DEFAULT_DATE, slack=true, text=true, rerun=false, verbose=false, customer_facing=true)
    @verbose = verbose
    report = self.weekly_report_logs.find_by(date: date)
    msg = ""
    if report == nil || rerun
      record_instance_logs(rerun)
      get_latest_prices
      usage = get_overall_usage(date == DEFAULT_DATE ? Date.today : date, customer_facing)

      start_date = Date.parse(self.start_date)
      if date < start_date
        puts "Given date is before the project start date"
        return
      elsif date > Date.today
        puts "Given date is in the future"
        return
      end
      start_date = start_date > date.beginning_of_month ? start_date : date.beginning_of_month
      compute_costs_this_month = @explorer.get_cost_and_usage(compute_cost_query(start_date, date + 1, "MONTHLY")).results_by_time[0]
      compute_costs = compute_costs_this_month.total["UnblendedCost"][:amount].to_f
      compute_costs = (compute_costs * CostLog::USD_GBP_CONVERSION * 12.5 * 1.25).ceil

      data_egress_this_month = @explorer.get_cost_and_usage(data_out_query(start_date, date + 1, "MONTHLY")).results_by_time[0]
      data_egress_amount = data_egress_this_month.total["UsageQuantity"][:amount].to_f.ceil(2)
      data_egress_costs = data_egress_this_month.total["UnblendedCost"][:amount].to_f
      data_egress_costs = (data_egress_costs * CostLog::USD_GBP_CONVERSION * 12.5 * 1.25).ceil

      costs_this_month = @explorer.get_cost_and_usage(all_costs_query(start_date, date + 1, "MONTHLY")).results_by_time[0]
      total_costs = costs_this_month.total["UnblendedCost"][:amount].to_f
      total_costs = (total_costs * CostLog::USD_GBP_CONVERSION * 12.5 * 1.25).ceil

      latest_logs = self.instance_logs.where('timestamp LIKE ?', "%#{date == DEFAULT_DATE ? Date.today : date}%").where(compute: 1)
      instances_date = latest_logs.first ? Time.parse(latest_logs.first.timestamp) : (date == DEFAULT_DATE ? Time.now : date + 0.5)
      time_lag = (instances_date.to_date - date).to_i

      inbetween_costs = 0.0
      inbetween_dates = ((date + 1.day)...instances_date.to_date).to_a
      inbetween_dates.each do |date|
        self.instance_logs.where('timestamp LIKE ?', "%#{date}%").where(compute: 1).each do |log|
          if log.status.downcase == "running"
            inbetween_costs += @@prices[log.region][log.instance_type]
          end
        end
      end
      inbetween_costs = (inbetween_costs * CostLog::USD_GBP_CONVERSION * 24 * 12.5 * 1.25).ceil
      inbetween_costs = (inbetween_costs + (fixed_daily_cu_cost * inbetween_dates.count)).ceil

      future_costs = 0.0
      latest_logs.each do |log|
        if log.status.downcase == "running"
          future_costs += @@prices[log.region][log.instance_type]
        end
      end
      daily_future_cu = (future_costs * CostLog::USD_GBP_CONVERSION * 24 * 12.5 * 1.25).ceil
      total_future_cu = (daily_future_cu + fixed_daily_cu_cost).ceil

      remaining_budget = self.current_budget.to_i - total_costs
      remaining_days = (remaining_budget - inbetween_costs) / (daily_future_cu + fixed_daily_cu_cost)
      enough = (date + remaining_days) >= (date >> 1).beginning_of_month
      date_range = "1 - #{(date).day} #{Date::MONTHNAMES[date.month]}"
      date_warning = date > Date.today - 2 ? "\nWarning: AWS data takes roughly 48 hours to update, so these figures may be inaccurate\n" : nil

      msg = [
      "#{date_warning if date_warning}",
      ":calendar: \t\t\t\t Weekly Report for #{self.name} \t\t\t\t :calendar:",
      "*Monthly Budget:* #{self.current_budget} compute units",
      "*Compute Costs for #{date_range}:* #{compute_costs} compute units",
      "*Data Egress Costs for #{date_range}:* #{data_egress_costs} compute units (#{data_egress_amount} GB)",
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

  def get_latest_prices
    if @@prices == {}
      get_aws_instance_info
      File.foreach('aws_instance_details.txt').with_index do |entry, index|
        if index > 1
          entry = JSON.parse(entry)
          instance_type = entry['instance_type']
          region = entry['location']
          if !@@prices.has_key?(region)
            @@prices[region] = {}
          end

          if !@@prices[region].has_key?(instance_type)
            @@prices[region][instance_type] = entry['price_per_hour'].to_f
          end
        end
      end
    end
  end

  def get_compute_costs(start_date, end_date, rerun)
    compute_cost_log = nil
    if end_date == start_date + 1.day
      compute_cost_log = self.cost_logs.find_by(date: start_date.to_s, scope: "compute")
    end

    # for daily report, only make query if don't already have data in logs or asked to recalculate
    if !compute_cost_log || rerun
      groups = self.instance_logs.select(:compute_group).distinct.pluck(:compute_group).compact
      groups << "compute"
      groups.each do |group|
        begin
          response = @explorer.get_cost_and_usage(compute_cost_query(start_date, end_date, "DAILY", group)).results_by_time
        rescue Aws::CostExplorer::Errors::ServiceError, Seahorse::Client::NetworkingError => error
          raise AwsSdkError.new("Unable to determine compute costs for project #{self.name}. #{error if @verbose}") 
        end

        response.each do |day|
          date = day[:time_period][:start]
          compute_cost = day[:total]["UnblendedCost"][:amount].to_f
          log = self.cost_logs.find_by(date: date, scope: group)
          if rerun && log
            log.assign_attributes(cost: compute_cost, timestamp: Time.now.to_s)
            log.save!
          else
            log = CostLog.create(
              project_id: self.id,
              cost: compute_cost,
              currency: "USD",
              date: date,
              scope: group,
              timestamp: Time.now.to_s
            )
          end
          compute_cost_log = log if group == "compute"
        end
      end
    end
    compute_cost_log
  end

  def get_core_costs(start_date, end_date, rerun)
    core_cost_log = nil
    if end_date == start_date + 1.day
      core_cost_log = self.cost_logs.find_by(date: start_date.to_s, scope: "core")
    end

    # for daily report, only make query if don't already have data in logs or asked to recalculate
    if !core_cost_log || rerun
      begin
        response = @explorer.get_cost_and_usage(core_cost_query(start_date, end_date)).results_by_time
      rescue Aws::CostExplorer::Errors::ServiceError, Seahorse::Client::NetworkingError => error
        raise AwsSdkError.new("Unable to determine core costs for project #{self.name}. #{error if @verbose}") 
      end

      response.each do |day|
        date = day[:time_period][:start]
        core_cost = day[:total]["UnblendedCost"][:amount].to_f
        core_cost_log = self.cost_logs.find_by(date: date, scope: "core")
        if rerun && core_cost_log
          core_cost_log.assign_attributes(cost: core_cost, timestamp: Time.now.to_s)
          core_cost_log.save!
        else
          core_cost_log = CostLog.create(
            project_id: self.id,
            cost: core_cost,
            currency: "USD",
            date: date,
            scope: "core",
            timestamp: Time.now.to_s
          )
        end
      end
    end
    core_cost_log
  end

  def get_data_out_figures(start_date, end_date, rerun)
    data_out_cost_log = nil
    data_out_amount_log = nil
    if end_date == start_date + 1.day
      data_out_cost_log = self.cost_logs.find_by(date: start_date, scope: "data_out")
      data_out_amount_log = self.usage_logs.find_by(start_date: start_date, description: "data_out")
    end
    data_out_figures = nil
    # only make query if don't already have data in logs or asked to recalculate
    if !data_out_cost_log || !data_out_amount_log || rerun
      begin
        data_out_figures = @explorer.get_cost_and_usage(data_out_query(start_date, end_date)).results_by_time
      rescue Aws::CostExplorer::Errors::ServiceError, Seahorse::Client::NetworkingError => error
        raise AwsSdkError.new("Unable to determine data out figures for project #{self.name}. #{error if @verbose}") 
      end
      data_out_figures.each do |day|
        date = Date.parse(day[:time_period][:start])
        data_out_cost = day[:total]["UnblendedCost"][:amount]
        data_out_amount = day[:total]["UsageQuantity"][:amount]

        data_out_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "data_out")
        data_out_amount_log = self.usage_logs.find_by(start_date: date.to_s, description: "data_out")
      
        if data_out_cost_log && rerun
          data_out_cost_log.assign_attributes(cost: data_out_cost, timestamp: Time.now.to_s)
          data_out_cost_log.save!
        else
          data_out_cost_log = CostLog.create(
            project_id: self.id,
            cost: data_out_cost,
            currency: "USD",
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
    end
    return data_out_cost_log, data_out_amount_log
  end

  def get_storage_costs(start_date, end_date, rerun)
    storage_cost_log = nil
    if end_date == start_date + 1.day
      storage_cost_log = self.cost_logs.find_by(date: start_date.to_s, scope: "storage")
    end

    # for daily report, only make query if don't already have data in logs or asked to recalculate
    if !storage_cost_log || rerun
      begin
        response = @explorer.get_cost_and_usage(storage_cost_query(start_date, end_date)).results_by_time
      rescue Aws::CostExplorer::Errors::ServiceError, Seahorse::Client::NetworkingError => error
        raise AwsSdkError.new("Unable to determine storage costs for project #{self.name}. #{error if @verbose}") 
      end

      response.each do |day|
        date = day[:time_period][:start]
        storage_cost = day[:total]["UnblendedCost"][:amount].to_f
        storage_cost_log = self.cost_logs.find_by(date: date, scope: "storage")
        if rerun && storage_cost_log
          storage_cost_log.assign_attributes(cost: storage_cost, timestamp: Time.now.to_s)
          storage_cost_log.save!
        else
          storage_cost_log = CostLog.create(
            project_id: self.id,
            cost: storage_cost,
            currency: "USD",
            date: date,
            scope: "storage",
            timestamp: Time.now.to_s
          )
        end
      end
    end
    storage_cost_log
  end

  def get_total_costs(start_date, end_date, rerun)
    total_cost_log = nil
    if end_date == start_date + 1.day
      total_cost_log = self.cost_logs.find_by(date: start_date.to_s, scope: "total")
    end  
    # only make query if don't already have data in logs or asked to recalculate
    if !total_cost_log || rerun
      begin
        daily_costs = @explorer.get_cost_and_usage(all_costs_query(start_date, end_date)).results_by_time
      rescue Aws::CostExplorer::Errors::ServiceError, Seahorse::Client::NetworkingError => error
        raise AwsSdkError.new("Unable to determine total costs for project #{self.name}. #{error if @verbose}") 
      end
      daily_costs.each do |day|
        date = day[:time_period][:start]
        daily_cost = day[:total]["UnblendedCost"][:amount]
        total_cost_log = self.cost_logs.find_by(date: date, scope: "total")
        if total_cost_log && rerun
          total_cost_log.assign_attributes(cost: daily_cost, timestamp: Time.now.to_s)
          total_cost_log.save!
        else
          total_cost_log = CostLog.create(
            project_id: self.id,
            cost: daily_cost,
            currency: "USD",
            date: date,
            scope: "total",
            timestamp: Time.now.to_s
          )
        end
      end
    end
    total_cost_log
  end

  def get_overall_usage(date, customer_facing=false)
    logs = self.instance_logs.where('timestamp LIKE ? AND status IS NOT ?', "%#{date}%", "terminated").where(compute: 1)

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
        instance_counts[type]["total"] = instance_counts[type]["total"] + 1
      end
    end

    overall_usage = ""
    instance_counts.each do |type|
      overall_usage << "#{type[1]["total"]} "
      overall_usage << "x #{type[0]}"
      overall_usage << "(#{type[1]["stopped"]} stopped)" if type[1]["stopped"] != nil
      overall_usage << " "
    end
    overall_usage == "" ? "None recorded" : overall_usage.strip
  end

  def get_usage_hours(start_date, end_date, rerun=false)
    all_logs = []
    begin
      usage_by_instance_type = @explorer.get_cost_and_usage(compute_instance_type_usage_query(start_date, end_date))
    rescue Aws::CostExplorer::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      raise AwsSdkError.new("Unable to determine hours by instance type for project #{self.name}. #{error if @verbose}") 
    end
    usage_by_instance_type.results_by_time.each do |day|
      date = Date.parse(day[:time_period][:start])
      next_day = date + 1.day
      logs = self.usage_logs.where(unit: "hours").where(scope: "compute").where(start_date: date.to_s).where(end_date: next_day.to_s)
      logs.delete_all if rerun
      if !logs.any?
        day.groups.each do |group|
          instance_type = group[:keys][0]
          amount = group[:metrics]["UsageQuantity"][:amount].to_f.round(2)
          all_logs << UsageLog.create(
            project_id: self.id,
            description: instance_type,
            amount: amount,
            unit: "hours",
            scope: "compute",
            start_date: date.to_s,
            end_date: next_day.to_s,
            timestamp: Time.now
          )
        end
      else
        all_logs << logs
      end
    end
    all_logs.flatten
  end

  def get_usage_hours_by_instance_type(start_date=DEFAULT_DATE, rerun=false, customer_facing=false)
    logs = self.usage_logs.where(unit: "hours").where(scope: "compute").where(start_date: start_date).where(end_date: start_date + 1.day)
    logs = get_usage_hours(start_date, start_date + 1.day, rerun) if !logs.any? || rerun
    usage_breakdown = "\n\t\t\t\t"
    compute_other = []
    
    logs.each do |log|
      type = customer_facing ? log.customer_facing_type : log.description
      if type == "Compute (Other)"
        compute_other << log
      else
        usage_breakdown << "#{type}: #{log.amount} hours \n\t\t\t\t"
      end
    end

    compute_other_hours = compute_other.reduce(0.0) { |sum, log| sum + log.amount }.ceil(2)
    usage_breakdown << "Compute (Other): #{compute_other_hours} hours \n\t\t\t\t" if compute_other.any?
    usage_breakdown == "\n\t\t\t\t" ? "None" : usage_breakdown
  end

  def record_instance_logs(rerun=false)
    today_logs = self.instance_logs.where('timestamp LIKE ?', "%#{Date.today}%")
    today_logs.delete_all if rerun
    if today_logs.count == 0
      regions.reverse.each do |region|
        begin
          @instances_checker = Aws::EC2::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: region)
          results = nil
          results = @instances_checker.describe_instances(project_instances_query)
        rescue Aws::EC2::Errors::ServiceError, Seahorse::Client::NetworkingError => error
          raise AwsSdkError.new("Unable to determine AWS instances for project #{self.name} in region #{region}. #{error if @verbose}")
        rescue Aws::Errors::MissingRegionError => error
          raise AwsSdkError.new("Unable to determine AWS instances for project #{self.name} due to missing region. #{error if @verbose}")  
        end
        @instances_checker.describe_instances(project_instances_query).reservations.each do |reservation|
          reservation.instances.each do |instance|
            named = ""
            compute = false
            compute_group = nil
            instance.tags.each do |tag|
              if tag.key == "Name"
                named = tag.value
              end
              if tag.key == "compute"
                compute = tag.value == "true"
              end
              if tag.key == "compute_group"
                compute_group = tag.value
              end
            end

            InstanceLog.create(
              instance_id: instance.instance_id,
              project_id: self.id,
              instance_name: named,
              instance_type: instance.instance_type,
              compute: compute,
              compute_group: compute_group,
              status: instance.state.name,
              host: "AWS",
              region: region,
              timestamp: Time.now.to_s
            )
          end
        end
      end
    end
  end

  def get_data_out(date=DEFAULT_DATE)
    @explorer.get_cost_and_usage(data_out_query(date))
  end

  def record_logs_for_range(start_date, end_date, rerun=false)
    # AWS SDK does not include end date, so must increment by one day
    end_date = end_date + 1.day
    get_compute_costs(start_date, end_date, rerun)
    get_core_costs(start_date, end_date, rerun)
    get_data_out_figures(start_date, end_date, rerun)
    get_storage_costs(start_date, end_date, rerun)
    get_total_costs(start_date, end_date, rerun)
    get_usage_hours(start_date, end_date, rerun)
  end

  def get_aws_instance_info
    regions = AwsProject.all.map(&:regions).flatten.uniq | ["eu-west-2"]
    regions.sort!

    timestamp = begin
      Date.parse(File.open('aws_instance_details.txt').first) 
    rescue ArgumentError, Errno::ENOENT
      false
    end
    existing_regions = begin
      File.open('aws_instance_details.txt').first(2).last.chomp
    rescue Errno::ENOENT 
      false
    end

    if timestamp == false || Date.today - timestamp >= 1 || existing_regions == false || existing_regions != regions.to_s
      regions.each.with_index do |region, index|
        if index == 0
          File.write('aws_instance_details.txt', "#{Time.now}\n")
          File.write('aws_instance_details.txt', "#{regions}\n", mode: "a")
        end
        first_query = true
        results = nil
        while first_query || results&.next_token
          begin
            results = @pricing_checker.get_products(instances_info_query(region, results&.next_token))
          rescue Aws::Pricing::Errors::ServiceError, Aws::Errors::MissingRegionError, Seahorse::Client::NetworkingError => error
            raise AwsSdkError.new("Unable to determine AWS instances in region #{region}. #{error}")
          end
          results.price_list.each do |result|
            details = JSON.parse(result)
            attributes = details["product"]["attributes"]
            price = details["terms"]["OnDemand"]
            price = price[price.keys[0]]["priceDimensions"]
            price = price[price.keys[0]]["pricePerUnit"]["USD"].to_f
            mem = attributes["memory"].gsub(" GiB", "")
            info = {
              instance_type: attributes["instanceType"],
              location: region, 
              price_per_hour: price,
              cpu: attributes["vcpu"].to_i,
              mem: mem.to_f,
              gpu: attributes["gpu"] ? attributes["gpu"].to_i : 0
            }
            File.write('aws_instance_details.txt', "#{info.to_json}\n", mode: 'a')
          end
          first_query = false
        end
      end
    end
  end

  private

  def compute_cost_query(start_date, end_date=(start_date + 1), granularity="DAILY", group=nil)
    query = {
      time_period: {
        start: start_date.to_s,
        end: end_date.to_s
      },
      granularity: granularity,
      metrics: ["UNBLENDED_COST"],
      filter: {
        and:[ 
          {
            not: {
              dimensions: {
                key: "RECORD_TYPE",
                values: ["CREDIT"]
              }
            }
          },
          {
            dimensions: {
              key: "USAGE_TYPE_GROUP",
              values: ["EC2: Running Hours"]
            }
          },
          {
            dimensions: {
              key: "SERVICE",
              values: ["Amazon Elastic Compute Cloud - Compute"]
            }
          },
          {
            tags: {
              key: "compute",
              values: ["true"]
            }
          },
        ]
      },
    }
    query[:filter][:and] << project_filter if filter_level == "tag"
    query[:filter][:and] << compute_group_filter(group) if group && group != "compute"
    query
  end

  def core_cost_query(start_date, end_date=(start_date + 1), granularity="DAILY")
    query = {
      time_period: {
        start: start_date.to_s,
        end: end_date.to_s
      },
      granularity: granularity,
      metrics: ["UNBLENDED_COST"],
      filter: {
        and:[ 
          {
            not: data_out_filter
          },
          {
            not: storage_filter
          },
          {
            not: {
              dimensions: {
                key: "RECORD_TYPE",
                values: ["CREDIT"]
              }
            }
          },
          {
            tags: {
              key: "core",
              values: ["true"]
            }
          },
        ]
      },
    }
    query[:filter][:and] << project_filter if filter_level == "tag"
    query
  end

  def all_costs_query(start_date, end_date=(start_date + 1), granularity="DAILY")
    query = {
      time_period: {
        start: "#{start_date.to_s}",
        end: "#{end_date.to_s}"
      },
      granularity: granularity,
      metrics: ["UNBLENDED_COST"],
      filter: {
        and:[ 
          {
            not: {
              dimensions: {
                key: "RECORD_TYPE",
                values: ["CREDIT"]
              }
            }
          },
          {
            not: {
              dimensions: {
                key: "SERVICE",
                values: ["Tax"]
              }
            }
          },
        ]
      },
    }
    query[:filter][:and] << project_filter if filter_level == "tag"
    query
  end

  def compute_instance_type_usage_query(start_date, end_date=start_date + 1.day)
    query = {
      time_period: {
        start: start_date.to_s,
        end: end_date.to_s
      },
      granularity: "DAILY",
      metrics: ["USAGE_QUANTITY"],
      filter: {
        and: [
          { 
            dimensions: {
              key: "SERVICE",
              values: ["Amazon Elastic Compute Cloud - Compute"]
            }
          },
          {
            dimensions: {
              key: "USAGE_TYPE_GROUP",
              values: ["EC2: Running Hours"]
            }
          },
          {
            tags: {
              key: "compute",
              values: ["true"]
            }
          }
        ]
      },
      group_by: [{type: "DIMENSION", key: "INSTANCE_TYPE"}]
    }
    query[:filter][:and] << project_filter if filter_level == "tag"
    query
  end

  def data_out_query(start_date, end_date=start_date + 1, granularity="DAILY")
    query = {
      time_period: {
        start: start_date.to_s,
        end: end_date.to_s
      },
      granularity: granularity,
      metrics: ["UNBLENDED_COST", "USAGE_QUANTITY"],
      filter: {
        and: [
          data_out_filter,
          {
            not: {
              dimensions: {
                key: "RECORD_TYPE",
                values: ["CREDIT"]
              }
            }
          },
          {
            not: {
              dimensions: {
                key: "SERVICE",
                values: ["Tax"]
              }
            }
          }
        ]
      }
    }
    query[:filter][:and] << project_filter if filter_level == "tag"
    query
  end

  def storage_cost_query(start_date, end_date=start_date+1, granularity="DAILY")
    query = {
      time_period: {
        start: start_date.to_s,
        end: end_date.to_s
      },
      granularity: granularity,
      metrics: ["UNBLENDED_COST", "USAGE_QUANTITY"],
      filter: {
        and: [
          storage_filter,
          {
            not: {
              dimensions: {
                key: "RECORD_TYPE",
                values: ["CREDIT"]
              }
            }
          },
          {
            not: {
              dimensions: {
                key: "SERVICE",
                values: ["Tax"]
              }
            }
          }
        ]
      }
    }
    query[:filter][:and] << project_filter if filter_level == "tag"
    query
  end

  def instances_info_query(region, token=nil)
    details = {
      service_code: "AmazonEC2",
      filters: [ 
        {
          field: "location", 
          type: "TERM_MATCH", 
          value: @@region_mappings[region], 
        },
        {
          field: "tenancy",
          type: "TERM_MATCH",
          value: "shared"
        },
        {
          field: "capacitystatus",
          type: "TERM_MATCH",
          value: "UnusedCapacityReservation"
        },
        {
          field: "operatingSystem",
          type: "TERM_MATCH",
          value: "linux"
        },
        {
          field: "preInstalledSW",
          type: "TERM_MATCH", 
          value: "NA"
        }
     ], 
     format_version: "aws_v1"
    }
    details[:next_token] = token if token
    details
  end

  def project_instances_query
    if filter_level == "tag"
      {
        filters: [
          {
            name: "tag:project", 
            values: [self.name], 
          }, 
        ], 
      }
    end
  end

  def project_filter
    {
      tags: {
        key: "project",
        values: [self.name]
      }
    }
  end

  def compute_group_filter(group)
    {
      tags: {
        key: "compute_group",
        values: [group]
      }
    }
  end

  def data_out_filter
    {
      dimensions: {
        key: "USAGE_TYPE_GROUP",
        values: 
          [
            "EC2: Data Transfer - Internet (Out)",
            "EC2: Data Transfer - CloudFront (Out)",
            "EC2: Data Transfer - Region to Region (Out)"
          ]
      }
    }
  end

  def storage_filter
    { 
      dimensions: {
        key: "USAGE_TYPE_GROUP",
        values: 
          [
            "S3: Storage - Standard",
            "EC2: EBS - I/O Requests",
            "EC2: EBS - Magnetic",
            "EC2: EBS - Provisioned IOPS",
            "EC2: EBS - SSD(gp2)",
            "EC2: EBS - SSD(io1)",
            "EC2: EBS - Snapshots",
            "EC2: EBS - Optimized"
          ]
      }
    }
  end
end

class AwsSdkError < StandardError
  attr_accessor :error_messages
  def initialize(msg)
    @error_messages = []
    super(msg)
  end
end
