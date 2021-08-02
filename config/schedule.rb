# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever

every :day, at: '12pm' do
  rake "daily_reports"
end

every :day, at: '12am' do
  rake "azure_prices"
  rake "azure_instance_sizes"
  rake "aws_instance_info"
end

every :monday, at: '12pm' do
  rake "weekly_reports"
end

every 5.minutes do
  command "ruby #{File.expand_path("..", File.dirname(__FILE__))}/record_instance_logs.rb all rerun"
end
