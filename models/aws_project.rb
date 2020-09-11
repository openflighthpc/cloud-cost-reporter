require 'aws-sdk'
load './models/project.rb'

class AwsProject < Project
  after_initialize :add_explorer

  def add_explorer
    @explorer = Aws::CostExplorer::Client.new(access_key_id: self.access_key_ident, secret_access_key: self.key)
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
    msg = "
      :crystal_ball: Forecast for #{Date.today} :crystal_ball:
      *USD:* #{forecast_cost.round(2)}
      *Total EC2 Hours:* #{forecast_hours.round(2)}
    "

    send_slack_message(msg)
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
end
