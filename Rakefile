# update with your token
slack_token = ""

desc 'Run daily reports'
task :daily_reports do
  system("SLACK_TOKEN=#{slack_token} ruby daily_reports.rb all latest slack")
end

desc 'Run daily reports'
task :daily_reports do
  system("SLACK_TOKEN=#{slack_token} ruby weekly_reports.rb all latest slack")
end
