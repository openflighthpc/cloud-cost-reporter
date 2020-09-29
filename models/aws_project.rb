require 'aws-sdk-costexplorer'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-ec2'
require 'aws-sdk-pricing'
require_relative 'project'

class AwsProject < Project
  @@prices = {}

  after_initialize :add_sdk_objects

  def access_key_ident
    @metadata['access_key_ident']
  end

  def key
    @metadata['key']
  end

  def region
    @metadata['region']
  end

  def account_id 
    @metadata['account_id']
  end

  def filter_level
    @metadata['filter_level']
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
    @instances_checker = Aws::EC2::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: self.region)
    @pricing_checker = Aws::Pricing::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
  end

  def daily_report(date=(Date.today - 2), slack=true, text=true, rerun=false, verbose=false)
    @verbose = false
    start_date = Date.parse(self.start_date)
    if date < start_date
      puts "Given date is before the project start date"
      return
    elsif date > Date.today
      puts "Given date is in the future"
      return
    end

    record_instance_logs(rerun) if date >= Date.today - 2 && date <= Date.today
    
    cached = !rerun && self.cost_logs.find_by(date: date.to_s, scope: "total")

    compute_cost_log = get_compute_costs(date, rerun)
    data_out_cost_log, data_out_amount_log = get_data_out_figures(date, rerun)
    total_cost_log = get_total_costs(date, rerun)
    overall_usage = get_overall_usage(date)
    usage_breakdown = get_usage_hours_by_instance_type(date, rerun)

    date_warning = date > Date.today - 2 ? "\nWarning: AWS data takes roughly 48 hours to update, so these figures may be inaccurate\n" : nil

    msg = [
      "#{date_warning if date_warning}",
      "#{"*Cached report*" if cached}",
      ":moneybag: Usage for #{(date).to_s} :moneybag:",
      "*Compute Costs (USD):* #{compute_cost_log.cost.to_f.ceil(2)}",
      "*Compute Units (Flat):* #{compute_cost_log.compute_cost}",
      "*Compute Units (Risk):* #{compute_cost_log.risk_cost}\n",
      "*Data Out (GB):* #{data_out_amount_log.amount.to_f.ceil(4)}",
      "*Data Out Costs (USD):* #{data_out_cost_log.cost.to_f.ceil(2)}",
      "*Compute Units (Flat):* #{data_out_cost_log.compute_cost}",
      "*Compute Units (Risk):* #{data_out_cost_log.risk_cost}\n",
      "*Total Costs(USD):* #{total_cost_log.cost.to_f.ceil(2)}",
      "*Total Compute Units (Flat):* #{total_cost_log.compute_cost}",
      "*Total Compute Units (Risk):* #{total_cost_log.risk_cost}\n",
      "*FC Credits:* #{total_cost_log.fc_credits_cost}",
      "*Compute Instance Usage:* #{overall_usage.strip}",
      "*Compute Instance Hours:* #{usage_breakdown}"
    ].join("\n") + "\n"

    send_slack_message(msg) if slack

    if text
      puts "\nProject: #{self.name}"
      puts msg.gsub(":moneybag:", "").gsub("*", "").gsub("\t", "")
      puts "_" * 50
    end
  end

  def weekly_report(date=Date.today - 2, slack=true, text=true, rerun=false, verbose=false)
    @verbose = false
    report = self.weekly_report_logs.find_by(date: date)
    msg = ""
    if report == nil || rerun
      record_instance_logs(rerun)
      get_latest_prices
      usage = get_overall_usage(date == Date.today - 2 ? Date.today : date, true)

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
      compute_costs = (compute_costs * CostLog::USD_GBP_CONVERSION * 10 * 1.25).ceil

      data_egress_this_month = @explorer.get_cost_and_usage(data_out_query(start_date, date + 1, "MONTHLY")).results_by_time[0]
      data_egress_amount = data_egress_this_month.total["UsageQuantity"][:amount].to_f.ceil(2)
      data_egress_costs = data_egress_this_month.total["UnblendedCost"][:amount].to_f
      data_egress_costs = (data_egress_costs * CostLog::USD_GBP_CONVERSION * 10 * 1.25).ceil

      costs_this_month = @explorer.get_cost_and_usage(all_costs_query(start_date, date + 1, "MONTHLY")).results_by_time[0]
      total_costs = costs_this_month.total["UnblendedCost"][:amount].to_f
      total_costs = (total_costs * CostLog::USD_GBP_CONVERSION * 10 * 1.25).ceil

      logs = self.instance_logs.where('timestamp LIKE ?', "%#{date == Date.today - 2 ? Date.today : date}%").where(compute: 1)
      future_costs = 0.0
      logs.each do |log|
        if log.status.downcase == "running"
          future_costs += @@prices[self.region][log.instance_type]
        end
      end
      daily_future_cu = (future_costs * CostLog::USD_GBP_CONVERSION * 24 * 10 * 1.25).ceil
      total_future_cu = (daily_future_cu + fixed_daily_cu_cost).ceil

      remaining_budget = self.budget.to_i - total_costs
      remaining_days = remaining_budget / (daily_future_cu + fixed_daily_cu_cost)
      instances_date = logs.first ? Time.parse(logs.first.timestamp) : (date == Date.today - 2 ? Time.now : date + 0.5)
      time_lag = (instances_date.to_date - date).to_i
      enough = (date + remaining_days + time_lag) >= (date >> 1).beginning_of_month
      date_range = "1 - #{(date).day} #{Date::MONTHNAMES[date.month]}"
      date_warning = date > Date.today - 2 ? "\nWarning: AWS data takes roughly 48 hours to update, so these figures may be inaccurate\n" : nil

      msg = [
      "#{date_warning if date_warning}",
      ":calendar: \t\t\t\t Weekly Report for #{self.name} \t\t\t\t :calendar:",
      "*Monthly Budget:* #{self.budget} compute units",
      "*Compute Costs for #{date_range}:* #{compute_costs} compute units",
      "*Data Egress Costs for #{date_range}:* #{data_egress_costs} compute units (#{data_egress_amount} GB)",
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

  def get_latest_prices
    instance_types = self.instance_logs.where(host: "AWS").group(:instance_type).pluck(:instance_type)
    instance_types.each do |instance_type|
      if !@@prices.has_key?(self.region)
        @@prices[region] = {}
      end
      if !@@prices[self.region].has_key?(instance_type)
        @@prices[self.region][instance_type] = get_cost_per_hour(instance_type)
      end
    end
  end

  def get_compute_costs(date, rerun)
    compute_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "compute")

    # only make query if don't already have data in logs or asked to recalculate
    if !compute_cost_log || rerun
      compute_cost = @explorer.get_cost_and_usage(compute_cost_query(date)).results_by_time[0][:total]["UnblendedCost"][:amount].to_f
      if rerun && compute_cost_log
        compute_cost_log.assign_attributes(cost: compute_cost, timestamp: Time.now.to_s)
        compute_cost_log.save!
      else
        compute_cost_log = CostLog.create(
          project_id: self.id,
          cost: compute_cost,
          currency: "USD",
          date: date.to_s,
          scope: "compute",
          timestamp: Time.now.to_s
        )
      end
    end
    compute_cost_log
  end

  def get_data_out_figures(date, rerun)
    data_out_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "data_out")
    data_out_amount_log = self.usage_logs.find_by(start_date: date.to_s, description: "data_out")
    data_out_figures = nil
    # only make query if don't already have data in logs or asked to recalculate
    if !data_out_cost_log || !data_out_amount_log || rerun
      data_out_figures = @explorer.get_cost_and_usage(data_out_query(date)).results_by_time[0]
      data_out_cost = data_out_figures.total["UnblendedCost"][:amount]
      data_out_amount = data_out_figures.total["UsageQuantity"][:amount]
      
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
    return data_out_cost_log, data_out_amount_log
  end

  def get_total_costs(date, rerun)
    total_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "total")
    # only make query if don't already have data in logs or asked to recalculate
    if !total_cost_log || rerun
      daily_cost = @explorer.get_cost_and_usage(all_costs_query(date)).results_by_time[0].total["UnblendedCost"][:amount]
      if total_cost_log && rerun
        total_cost_log.assign_attributes(cost: daily_cost, timestamp: Time.now.to_s)
        total_cost_log.save!
      else
        total_cost_log = CostLog.create(
          project_id: self.id,
          cost: daily_cost,
          currency: "USD",
          date: date.to_s,
          scope: "total",
          timestamp: Time.now.to_s
        )
      end
    end
    total_cost_log
  end

  def get_cost_per_hour(resource_name)
    result = @pricing_checker.get_products(pricing_query(resource_name)).price_list
    details = JSON.parse(result.first)["terms"]["OnDemand"]
    details = details[details.keys[0]]["priceDimensions"]
    details[details.keys[0]]["pricePerUnit"]["USD"].to_f
  end

  def get_forecasts
    forecast_cost = @explorer.get_cost_forecast(cost_forecast_query).forecast_results_by_time[0].mean_value.to_f
    forecast_hours = @explorer.get_usage_forecast(usage_forecast_query).forecast_results_by_time[0].mean_value.to_f
    forecast_cost_rest_of_month = @explorer.get_cost_forecast(rest_of_month_cost_forecast_query).forecast_results_by_time[0].mean_value.to_f
    msg = "
    :crystal_ball: Forecast for #{Date.today} :crystal_ball:
    *USD:* #{forecast_cost.round(2)}
    *Total EC2 Hours:* #{forecast_hours.round(2)}
    *USD for rest of month:* #{forecast_cost_rest_of_month.round(2)}
    "

    send_slack_message(msg)
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

  def get_usage_hours_by_instance_type(date=(Date.today - 2), rerun)
    logs = self.usage_logs.where(unit: "hours").where(scope: "compute").where(start_date: date).where(end_date: date + 1)
    logs.delete_all if rerun
    usage_breakdown = "\n\t\t\t\t"
    if !logs.any?
      usage_by_instance_type = @explorer.get_cost_and_usage(compute_instance_type_usage_query(date))

      usage_by_instance_type.results_by_time[0].groups.each do |group|
        instance_type = group[:keys][0]
        amount = group[:metrics]["UsageQuantity"][:amount].to_f.round(2)
        usage_breakdown << "#{instance_type}: #{amount} hours \n\t\t\t\t"
        UsageLog.create(
          project_id: self.id,
          description: instance_type,
          amount: amount,
          unit: "hours",
          scope: "compute",
          start_date: date,
          end_date: date + 1,
          timestamp: Time.now
        )
      end
    else
      logs.each do |log|
        usage_breakdown = "#{log.description}: #{log.amount} hours \n\t\t\t\t"
      end
    end

    usage_breakdown == "\n\t\t\t\t" ? "None" : usage_breakdown
  end

  def record_instance_logs(rerun=false)
    today_logs = self.instance_logs.where('timestamp LIKE ?', "%#{Date.today}%")
    today_logs.delete_all if rerun
    if today_logs.count == 0
      @instances_checker.describe_instances(project_instances_query).reservations.each do |reservation|
        reservation.instances.each do |instance|
          named = ""
          compute = false
          instance.tags.each do |tag|
            if tag.key == "Name"
              named = tag.value
            end
            if tag.key == "compute"
              compute = tag.value == "true"
            end
          end

          InstanceLog.create(
            instance_id: instance.instance_id,
            project_id: self.id,
            instance_name: named,
            instance_type: instance.instance_type,
            compute: compute,
            status: instance.state.name,
            host: "AWS",
            timestamp: Time.now.to_s
          )
        end
      end
    end
  end

  def each_instance_usage_data
    @explorer.get_cost_and_usage_with_resources(each_instance_usage_query)
  end

  def get_instance_usage_data(instance_id)
    hours = @explorer.get_cost_and_usage_with_resources(instance_usage_query(instance_id))
    cost = @explorer.get_cost_and_usage_with_resources(instance_cost_query(instance_id))
  end

  def get_data_out(date=Date.today - 2)
    @explorer.get_cost_and_usage(data_out_query(date))
  end

  def get_ssd_usage
    @explorer.get_cost_and_usage(ssd_usage_query)
  end

    private

  def instance_type_usage_query(date) 
    {
      time_period: {
        start: date.to_s,
        end: (date + 1).to_s
      },
      granularity: "DAILY",
      metrics: ["USAGE_QUANTITY"],
      filter: {
        and: [
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
          },
          project_filter
        ]
      },
      group_by: [{type: "DIMENSION", key: "INSTANCE_TYPE"}]
    }
  end

  def compute_cost_query(start_date, end_date=(start_date + 1), granularity="DAILY")
    {
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
          project_filter
        ]
      },
    }
  end

  def all_costs_query(start_date, end_date=(start_date + 1), granularity="DAILY")
    {
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
          project_filter
        ]
      },
    }
  end

  def usage_forecast_query
    {
      time_period: {
        start: Date.today.to_s,
        end: (Date.today + 1).to_s
      },
      granularity: "DAILY",
      metric: "USAGE_QUANTITY",
      filter: {
        dimensions: {
          key: "USAGE_TYPE_GROUP",
          values: ["EC2: Running Hours"]
        }
      }
    }
  end

  def cost_forecast_query
    {
      time_period: {
        start: (Date.today).to_s,
        end: (Date.today + 1).to_s
      },
      granularity: "DAILY",
      metric: "UNBLENDED_COST",
      filter: {
        not: {
          dimensions: {
            key: "RECORD_TYPE",
            values: ["CREDIT"]
          }
        }
      }
    }
  end

  def rest_of_month_cost_forecast_query
    {
      time_period: {
        start: (Date.today).to_s,
        end: ((Date.today >> 1) - Date.today.day + 1).to_s
      },
      granularity: "MONTHLY",
      metric: "UNBLENDED_COST",
      filter: {
        not: {
          dimensions: {
            key: "RECORD_TYPE",
            values: ["CREDIT"]
          }
        }
      }
    }
  end

  def each_instance_cost_query(start_date, end_date=(start_date + 1), granularity="DAILY")
    {
      time_period: {
        start: start_date.to_s,
        end: (start_date + 1).to_s
      },
      granularity: granularity,
      metrics: ["UNBLENDED_COST"],
      filter: {
        and: [
          {
            dimensions: {
              key: "SERVICE",
              values: ["Amazon Elastic Compute Cloud - Compute"]
            }
          },
          {
            not: {
              dimensions: {
                key: "RESOURCE_ID",
                values: excluded_instances
              }
            }
          },
        ]
      },
      group_by: [{type: "DIMENSION", key: "RESOURCE_ID"}]
    }
  end

  def per_instance_compute_instance_type_usage_query(date)
    {
      time_period: {
        start: date.to_s,
        end: (date + 1).to_s
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
            not: {
              dimensions: {
                key: "RESOURCE_ID",
                values: excluded_instances
              }
            }
          },
        ]
      },
      group_by: [{type: "DIMENSION", key: "INSTANCE_TYPE"}]
    }
  end

  def compute_instance_type_usage_query(date)
    {
      time_period: {
        start: date.to_s,
        end: (date + 1).to_s
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
          project_filter,
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
  end

  def each_instance_usage_query
    {
      time_period: {
        start: (Date.today - 2).to_s,
        end: (Date.today - 1).to_s
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
            not: {
              dimensions: {
                key: "RESOURCE_ID",
                values: excluded_instances
              }
            }
          },
        ]
      },
      group_by: [{type: "DIMENSION", key: "INSTANCE_TYPE"}]
    }
  end

  def instance_usage_query(id)
    {
      time_period: {
        start: (Date.today - 2).to_s,
        end: (Date.today - 1).to_s
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
              key: "RESOURCE_ID",
              values: [id]
            }
          },
          {
            dimensions: {
              key: "USAGE_TYPE_GROUP",
              values: ["EC2: Running Hours"]
            }
          }
        ]
      },
      group_by: [{type: "DIMENSION", key: "RESOURCE_ID"}]
    }
  end

  def instance_cost_query(id)
    {
      time_period: {
        start: (Date.today - 2).to_s,
        end: (Date.today - 1).to_s
      },
      granularity: "DAILY",
      metrics: ["UNBLENDED_COST"],
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
              key: "RESOURCE_ID",
              values: [id]
            }
          },
        ]
      },
      group_by: [{type: "DIMENSION", key: "RESOURCE_ID"}]
    }
  end

  def data_out_query(start_date, end_date=start_date + 1, granularity="DAILY")
    {
      time_period: {
        start: start_date.to_s,
        end: end_date.to_s
      },
      granularity: granularity,
      metrics: ["UNBLENDED_COST", "USAGE_QUANTITY"],
      filter: {
        and: [
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
          },
          project_filter,
          {
            not: {
              dimensions: {
                key: "RECORD_TYPE",
                values: ["CREDIT"]
              }
            }
          }
        ]
      }
    }
  end

  def ssd_usage_query
    {
      time_period: {
        start: (Date.today - 20).to_s,
        end: (Date.today - 1).to_s
      },
      granularity: "MONTHLY",
      metrics: ["UNBLENDED_COST", "USAGE_QUANTITY"],
      filter: {
        and: [
          {
            dimensions: {
            key: "USAGE_TYPE_GROUP",
            values: 
              ["EC2: EBS - SSD(gp2)"]
            }
          },
          {
            not: {
              dimensions: {
                key: "RECORD_TYPE",
                values: ["CREDIT"]
              }
            }
          }
        ]
      }
    }
  end

  def pricing_query(resource_name)
    {
      service_code: "AmazonEC2",
      filters: [ 
        {
          field: "instanceType", 
          type: "TERM_MATCH", 
          value: resource_name, 
        },
        {
          field: "location", 
          type: "TERM_MATCH", 
          value: "EU (London)", 
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
     format_version: "aws_v1",
     max_results: 1
    }
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
    else
      {
        filters: [
          {
            name: "owner-id",
            values: [self.account_id]
          }
        ]
      }
    end
  end

  def project_filter
    if filter_level == "tag"
      {
        tags: {
          key: "project",
          values: [self.name]
        }
      }
    else
      {
        dimensions: {
          key: "LINKED_ACCOUNT",
          values: [self.account_id]
        }
      }
    end
  end
end
