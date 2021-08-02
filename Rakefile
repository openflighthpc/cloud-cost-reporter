# update with your token
slack_token = ""

desc 'Run daily reports'
task :daily_reports do
  system("SLACK_TOKEN=#{slack_token} ruby daily_reports.rb all latest slack")
end

desc 'Run weekly reports'
task :weekly_reports do
  system("SLACK_TOKEN=#{slack_token} ruby weekly_reports.rb all latest slack")
end

desc 'Record all instance logs'
task :instance_logs do
  system("ruby record_instance_logs.rb all rerun")
end

desc 'Get latest azure prices'
task :azure_prices do
  system("ruby get_latest_azure_prices.rb")
end

desc 'Get latest azure instance sizes'
task :azure_instance_sizes do
  system("ruby get_latest_azure_instance_sizes.rb")
end

desc 'Get latest aws instance sizes and prices'
task :aws_instance_info do
  system("ruby get_latest_aws_instance_info.rb")
end
