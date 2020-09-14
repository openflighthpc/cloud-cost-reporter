require 'aws-sdk-costexplorer'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-ec2'
require 'aws-sdk-pricing'
load './models/project.rb'
load './models/cost_log.rb'
load './models/instance_log.rb'

class AwsProject < Project
  after_initialize :add_sdk_objects

  def add_sdk_objects
    @explorer = Aws::CostExplorer::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
    @watcher = Aws::CloudWatch::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: 'eu-west-2')
    @instances_checker = Aws::EC2::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: 'eu-west-2')
    @pricing_checker = Aws::Pricing::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
  end

  def get_cost_and_usage(date=(Date.today - 2))
    cost_log = self.cost_logs.where(date: date.to_s).first
    
    # only make query if don't already have data in logs
    if cost_log == nil
      daily_cost = @explorer.get_cost_and_usage(cost_query(date)).results_by_time[0].total["UnblendedCost"][:amount]
      cost_log = CostLog.create(
        project_id: self.id,
        cost: daily_cost,
        currency: "USD",
        date: date.to_s,
        timestamp: Time.now.to_s
      )
    end

    overall_usage = get_overall_usage(date)
    usage_breakdown = get_usage_hours_by_instance_type(date)

    msg = "
      :moneybag: Usage for #{(Date.today - 2).to_s} :moneybag:
       *USD:* #{cost_log.cost.to_f.ceil(2)}
       *Compute Units (Flat):* #{cost_log.compute_cost}
       *Compute Units (Risk):* #{cost_log.risk_cost}
       *FC Credits:* #{cost_log.fc_credits_cost}
       *Usage:* #{overall_usage}
       *Hours:* #{usage_breakdown}
    "

    send_slack_message(msg)
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

  def get_overall_usage(date)
    logs = self.instance_logs.where('timestamp LIKE ?', "%#{date}%")

    instance_counts = {}
    logs.each do |log|
      use = true
      excluded_instance_names.each do |name|
        if log.name.include?(name)
          use = false
          break
        end
      end
      if use == true
        if !instance_counts.has_key?(log.instance_type)
          instance_counts[log.instance_type] = {log.status => 1, "total" => 1}  
        else
          instance_counts[log.instance_type][log.status] = instance_counts[log.instance_type][log.status] + 1
          instance_counts[log.instance_type]["total"] = instance_counts[log.instance_type]["total"] + 1
        end
      end 
    end

    overall_usage = ""
    instance_counts.each do |type|
      overall_usage << " #{type[1]["total"]} "
      overall_usage << "x #{type[0]}"
      overall_usage << "(#{type[1]["stopped"]} stopped)" if type[1]["stopped"] != nil
    end
    overall_usage == "" ? "None" : overall_usage
  end

  def get_usage_hours_by_instance_type(date)
    usage_by_instance_type = @explorer.get_cost_and_usage(instance_type_usage_query(date))
    usage_breakdown = " "

    usage_by_instance_type.results_by_time[0].groups.each do |group|
      usage_breakdown << "#{group[:keys][0]}: #{group[:metrics]["UsageQuantity"][:amount].to_f.round(2)} hours \n\t\t\t\t\t"
    end

    usage_breakdown == "" ? "None" : usage_breakdown
  end

  def record_instance_logs
    if self.instance_logs.where('timestamp LIKE ?', "%#{Date.today - 2}%").count == 0
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
            timestamp: Time.now.to_s
          )
        end
      end
    end
  end

  def get_instance_usage_data(instance_id)
    hours = @explorer.get_cost_and_usage_with_resources(instance_usage_query(instance_id))
    cost = @explorer.get_cost_and_usage_with_resources(instance_cost_query(instance_id))
  end

  def get_instance_cpu_utilization(instance_id)
    @watcher.get_metric_statistics(instance_cpu_utilization_query(instance_id))
  end

  def get_some_pricing
    @pricing_checker.get_products(pricing_query)
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
        start: "#{date.to_s}",
        end: "#{(date + 1).to_s}"
      },
      granularity: "DAILY",
      metrics: ["USAGE_QUANTITY"],
      filter: {
        dimensions: {
          key: "USAGE_TYPE_GROUP",
          values: ["EC2: Running Hours"]
        }
      },
      group_by: [{type: "DIMENSION", key: "INSTANCE_TYPE"}]
    }
  end

  def cost_query(date)
    {
      time_period: {
        start: "#{date.to_s}",
        end: "#{(date + 1).to_s}"
      },
      granularity: "DAILY",
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
        start: "#{(Date.today).to_s}",
        end: "#{(Date.today + 1).to_s}"
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
        start: "#{(Date.today).to_s}",
        end: "#{(Date.today + 1).to_s}"
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
        start: "#{(Date.today).to_s}",
        end: "#{((Date.today >> 1) - Date.today.day + 1).to_s}"
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

  def instance_usage_query(id)
    {
      time_period: {
        start: "#{(Date.today - 2).to_s}",
        end: "#{(Date.today - 1).to_s}"
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
        start: "#{(Date.today - 2).to_s}",
        end: "#{(Date.today - 1).to_s}"
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

  def pricing_query
    {
      filters: [
        {
          field: "ServiceCode", 
          type: "TERM_MATCH", 
          value: "AmazonEC2", 
        }, 
        {
          field: "volumeType", 
          type: "TERM_MATCH", 
          value: "Provisioned IOPS", 
        }, 
        {
          field: "location",
          type: "TERM_MATCH",
          value: "London"
        }
      ], 
      format_version: "aws_v1", 
      max_results: 1, 
    }
  end

  def data_out_query
    {
      time_period: {
        start: "#{(Date.today - 2).to_s}",
        end: "#{(Date.today - 1).to_s}"
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
        start: "#{(Date.today - 2).to_s}",
        end: "#{(Date.today - 1).to_s}"
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
end
