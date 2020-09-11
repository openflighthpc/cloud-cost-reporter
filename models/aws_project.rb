require 'aws-sdk-costexplorer'
require 'aws-sdk-cloudwatch'
load './models/project.rb'

class AwsProject < Project
  after_initialize :add_explorer

  def add_explorer
    @explorer = Aws::CostExplorer::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
    @watcher = Aws::CloudWatch::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key, region: 'eu-west-2')
  end

  def get_cost_and_usage
    daily_cost = @explorer.get_cost_and_usage(cost_query).results_by_time[0].total["UnblendedCost"][:amount]
    compute_units = (daily_cost.to_f * 10).ceil
    risk_units = (compute_units * 1.25).ceil

    usage_by_instance_type = @explorer.get_cost_and_usage(instance_type_usage_query)
    usage = ""

    usage_by_instance_type.results_by_time[0].groups.each do |group|
      usage << "#{group[:keys][0]}: #{group[:metrics]["UsageQuantity"][:amount].to_f.round(2)} hours \n\t\t\t "
    end

    usage = usage == "" ? "None" : usage

    msg = "
      :moneybag: Usage for #{(Date.today - 2).to_s} :moneybag:
      *USD:* #{daily_cost.to_f.round(2)}
      *Compute Units (Flat):* #{compute_units}
      *Compute Units (Risk):* #{risk_units}
      *Usage:* #{usage}
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

  def get_instance_usage_data(instance_id)
    hours = @explorer.get_cost_and_usage_with_resources(instance_usage_query(instance_id))
    cost = @explorer.get_cost_and_usage_with_resources(instance_cost_query(instance_id))
  end

  def get_instance_cpu_utlization(instance_id)
    puts @watcher.get_metric_statistics(instance_cpu_utilization_query(instance_id))
  end

  private

  def instance_type_usage_query 
    {
      time_period: {
        start: "#{(Date.today - 2).to_s}",
        end: "#{(Date.today - 1).to_s}"
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

  def cost_query
    {
      time_period: {
        start: "#{(Date.today - 2).to_s}",
        end: "#{(Date.today - 1).to_s}"
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
end
