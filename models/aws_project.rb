require 'aws-sdk-costexplorer'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-ec2'
require 'aws-sdk-pricing'
require_relative 'project'
require_relative 'cost_log'
require_relative 'instance_log'

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

  def excluded_instances
    @excluded_instances ||= self.instance_logs.select {|i| !i.compute_node?}.map {|i| i.instance_id}.uniq
    # if given an empty array the relevant queries will fail, so instead provide a dummy instance.
    @excluded_instances.length == 0 ? ["abc"] : @excluded_instances
  end

  def add_sdk_objects
    @metadata = JSON.parse(self.metadata)
    Aws.config.update({region: "us-east-1"})
    @explorer = Aws::CostExplorer::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
    @watcher = Aws::CloudWatch::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: 'eu-west-2')
    @instances_checker = Aws::EC2::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: 'eu-west-2')
    @pricing_checker = Aws::Pricing::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
  end

  def get_cost_and_usage(date=(Date.today - 2), slack=true)
    start_date = Date.parse(self.start_date)
    if date < start_date
      puts "Given date is before the project start date"
      return
    end

    compute_cost_log = self.cost_logs.where(date: date.to_s).first

    # only make query if don't already have data in logs
    if !compute_cost_log
      compute_instance_costs = @explorer.get_cost_and_usage_with_resources(each_instance_cost_query(date)).results_by_time[0][:groups]
      compute_cost = 0
      compute_instance_costs.each do |instance|
        compute_cost += instance[:metrics]["UnblendedCost"][:amount].to_f
      end
      
      compute_cost_log = CostLog.create(
        project_id: self.id,
        cost: compute_cost,
        currency: "USD",
        date: date.to_s,
        scope: "compute",
        timestamp: Time.now.to_s
        )
    end

    total_cost_log = self.cost_logs.find_by(date: date.to_s, scope: "total")
    
    # only make query if don't already have data in logs
    if !total_cost_log
      daily_cost = @explorer.get_cost_and_usage(all_costs_query(date)).results_by_time[0].total["UnblendedCost"][:amount]
      total_cost_log = CostLog.create(
        project_id: self.id,
        cost: daily_cost,
        currency: "USD",
        date: date.to_s,
        scope: "total",
        timestamp: Time.now.to_s
        )
    end

    overall_usage = get_overall_usage(date)
    usage_breakdown = get_usage_hours_by_instance_type(date)

    if slack
      msg = "
      :moneybag: Usage for #{(Date.today - 2).to_s} :moneybag:
      *Compute Costs (USD):* #{compute_cost_log.cost.to_f.ceil(2)}
      *Compute Units (Flat):* #{compute_cost_log.compute_cost}
      *Compute Units (Risk):* #{compute_cost_log.risk_cost}

      *Total Costs(USD):* #{total_cost_log.cost.to_f.ceil(2)}
      *Total Compute Units (Flat):* #{total_cost_log.compute_cost}
      *Total Compute Units (Risk):* #{total_cost_log.risk_cost}

      *FC Credits:* #{total_cost_log.fc_credits_cost}
      *Compute Instance Usage:* #{overall_usage}
      *Compute Instance Hours:* #{usage_breakdown}
      "

      send_slack_message(msg)
    end

    puts "\nProject: #{self.name}"
    puts "Usage for #{date.to_s}"
    puts "Compute Costs (USD): #{compute_cost_log.cost.to_f.ceil(2)}"
    puts "Compute Units (Flat): #{compute_cost_log.compute_cost}"
    puts "Compute Units (Risk): #{compute_cost_log.risk_cost}"
    puts "\nTotal Costs (USD): #{total_cost_log.cost.to_f.ceil(2)}"
    puts "Total Compute Units (Flat): #{total_cost_log.compute_cost}"
    puts "Total Compute Units (Risk): #{total_cost_log.risk_cost}"
    puts "\nFC Credits: #{total_cost_log.fc_credits_cost}"
    puts "Compute Instance Usage: #{overall_usage}"
    puts "Compute Instance Hours:"
    puts "#{usage_breakdown.strip.gsub("\t", "")}\n"
    puts "_" * 50
  end

  def weekly_report(date=Date.today, slack=true, rerun=false)
    report = self.weekly_report_logs.find_by(date: date)
    msg = ""
    if report == nil || rerun
      if date != Date.today
        puts "No weekly report for project #{self.name} on #{date}." 
        puts "As the contained data is time specific, can only retrieve saved reports or generate one for today.\n\n"
        reports = self.weekly_report_logs
        if reports.length > 0
          puts "Weekly reports exist for project #{self.name} on the following dates: " 
          self.weekly_report_logs.each do |report|
            puts report.date
          end
        else
          puts "No prior weekly reports exist for #{self.name}."
        end
        puts "_" * 50
        puts ""
        return
      end
      record_instance_logs(rerun)
      get_latest_prices
      usage = get_overall_usage(date, true)

      start_date = Date.parse(self.start_date)
      if date < start_date
        puts "Given date is before the project start date"
        return
      end
      start_date = start_date > Date.today.beginning_of_month ? start_date : Date.today.beginning_of_month
      costs_this_month = @explorer.get_cost_and_usage(all_costs_query(start_date, Date.today - 2, "MONTHLY")).results_by_time[0]
      total_costs = costs_this_month.total["UnblendedCost"][:amount].to_f
      total_costs = (total_costs * 10 * 1.25).ceil

      logs = self.instance_logs.where('timestamp LIKE ?', "%#{Date.today}%").select {|log| log.compute_node?}
      future_costs = 0.0
      logs.each do |log|
        if log.status == "running"
          future_costs += @@prices[self.region][log.instance_type]
        end
      end
      daily_future_cu = (future_costs * 24 * 10 * 1.25).ceil
      total_future_cu = (daily_future_cu + fixed_daily_cu_cost).ceil

      remaining_budget = self.budget.to_i - total_costs
      remaining_days = remaining_budget / (daily_future_cu + fixed_daily_cu_cost)
      enough = Date.today + remaining_days + 2 >= (Date.today << 1).beginning_of_month
      date_range = "1 - #{(Date.today - 2).day} #{Date::MONTHNAMES[Date.today.month]}"

      msg = "
      :calendar: \t\t\t\t Weekly Report for #{self.name} \t\t\t\t :calendar:
      *Monthly Budget:* #{self.budget} compute units
      *Total Costs for #{date_range}:* #{total_costs} compute units
      *Remaining Monthly Budget:* #{remaining_budget} compute units

      *Current Usage*
      Currently, the cluster compute nodes are:
      `#{usage}`

      The average cost for these compute nodes, in the above state, is about *#{daily_future_cu}* compute units per day.
      Other, fixed cluster costs are on average *#{fixed_daily_cu_cost}* compute units per day.

      The total estimated requirement is therefore *#{total_future_cu}* compute units per day.

      *Predicted Usage*
      "

      if remaining_budget < 0
        excess = (total_future_cu * Date.today.end_of_month.day - (Date.today - 2).day)
        msg << ":awooga:The monthly budget *has been exceeded*:awooga:. Based on current usage the budget will be exceeded by *#{excess}* 
      compute units at the end of the month."
      else
        msg << "Based on the current usage, the remaining budget will be used up in *#{remaining_days}* days.
      As tracking is *2 days behind*, the budget is predicted to therefore be *#{enough ? "sufficient" : ":awooga:insufficient:awooga:"}* for the rest of the month."
      end

      WeeklyReportLog.create(project_id: self.id, content: msg, date: Date.today, timestamp: Time.now)
    else
      msg = report.content
    end
    send_slack_message(msg) if slack
    puts (msg.gsub(":calendar:", "").gsub("*", "").gsub(":awooga:", ""))
    puts '_' * 50
  end

  def get_latest_prices
    instances = InstanceLog.where(host: "AWS").where('timestamp LIKE ?', "%#{Date.today}%")
    instances.each do |instance|
      if !@@prices.has_key?(self.region)
        @@prices[region] = {}
      end
      if !@@prices[self.region].has_key?(instance.instance_type)
        @@prices[self.region][instance.instance_type] = get_cost_per_hour(instance.instance_type)
      end
    end
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
    logs = self.instance_logs.where('timestamp LIKE ? AND status IS NOT ?', "%#{date}%", "terminated").select {|log| log.compute_node?}

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

  def get_usage_hours_by_instance_type(date=(Date.today - 2))
    usage_by_instance_type = @explorer.get_cost_and_usage_with_resources(compute_instance_type_usage_query(date))
    usage_by_instance_type
    usage_breakdown = "\n\t\t\t\t"

    usage_by_instance_type.results_by_time[0].groups.each do |group|
      usage_breakdown << "#{group[:keys][0]}: #{group[:metrics]["UsageQuantity"][:amount].to_f.round(2)} hours \n\t\t\t\t"
    end

    usage_breakdown == "\n\t\t\t\t" ? "None" : usage_breakdown
  end

  def record_instance_logs(rerun=false)
    today_logs = self.instance_logs.where('timestamp LIKE ?', "%#{Date.today}%")
    today_logs.delete_all if rerun
    if today_logs.count == 0 || rerun
      @instances_checker.describe_instances.reservations.each do |reservation|
        reservation.instances.each do |instance|
          named = ""
          instance.tags.each do |tag|
            if tag.key == "Name"
              named = tag.value
            end
          end
          
          InstanceLog.create(
            instance_id: instance.instance_id,
            project_id: self.id,
            instance_name: named,
            instance_type: instance.instance_type,
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

  def get_instance_cpu_utilization(instance_id)
    @watcher.get_metric_statistics(instance_cpu_utilization_query(instance_id))
  end

  def get_data_out
    @explorer.get_cost_and_usage(data_out_query)
  end

  def get_ssd_usage
    puts @explorer.get_cost_and_usage(ssd_usage_query)
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
            cost_categories: {
              key: "compute",
              values: ["compute"]
            }
          }
        ]
      },
      group_by: [{type: "DIMENSION", key: "INSTANCE_TYPE"}]
    }
  end

  def cost_query(start_date, end_date=(start_date + 1), granularity="DAILY")
    {
      time_period: {
        start: start_date,
        end: end_date
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
            cost_categories: {
              key: "compute",
              values: ["compute"]
            }
          }
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
        not: {
          dimensions: {
            key: "RECORD_TYPE",
            values: ["CREDIT"]
          }
        }
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

  def instances_cpu_utilization_query
    {
      namespace: "AWS/EC2",
      metric_name: "CPUUtilization",
      start_time: Date.today.to_time.strftime('%Y-%m-%dT%H:%M:%S'),
      end_time: (Date.today + 1).to_time.strftime('%Y-%m-%dT%H:%M:%S'),
      period: 86400,
      statistics: ["Average", "Maximum"]
    }
  end

  def instance_cpu_utilization_query(id)
    {
      namespace: "AWS/EC2",
      metric_name: "CPUUtilization",
      dimensions: [
        {
          name: 'InstanceId',
          value: id
        }
      ],
      start_time: Date.today.to_time.strftime('%Y-%m-%dT%H:%M:%S'),
      end_time: (Date.today + 1).to_time.strftime('%Y-%m-%dT%H:%M:%S'),
      period: 86400,
      statistics: ["Average", "Maximum"]
    }
  end

  def data_out_query
    {
      time_period: {
        start: (Date.today - 2).to_s,
        end: (Date.today - 1).to_s
      },
      granularity: "DAILY",
      metrics: ["UNBLENDED_COST", "USAGE_QUANTITY"],
      filter: {
        and: [
          {
            dimensions: {
            key: "USAGE_TYPE_GROUP",
            values: 
              [
                "EC2: Data Transfer - Internet (Out)",
                "EC2: Data Transfer - CloudFront (Out)"
              ]
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

  def ssd_usage_query
    {
      time_period: {
        start: (Date.today - 2).to_s,
        end: (Date.today - 1).to_s
      },
      granularity: "DAILY",
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
end