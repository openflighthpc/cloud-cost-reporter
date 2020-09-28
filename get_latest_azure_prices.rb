require_relative './models/azure_project.rb'

# Need Azure credentials to get price list, so use a project in database.
# Assumes all projects are registered in the UK, using GBP and a 'pay as you go' pricing model.
project = AzureProject.where(host: 'azure').first
if !project
  puts "No Azure projects in database to retrieve price list"
else
  project.get_prices
end
