# cloud-cost-reporter

Tracker and reporting tool for Azure and AWS costs.

## Overview

A proof of concept application for tracking Azure and AWS costs and usage. Built in Ruby (no framework), with a basic SQLite database.

## Installation

This application requires Ruby (2.5.1) and a recent version of Bundler (2.1.4).

Some assembly is required post-clone:

```
cd /path/to/source
bundle install
ruby db/setup.rb
ruby db/add_instance_mappings.rb
```

## Configuration

### AWS

On AWS, projects can be tracked on an account or project tag level. For tracking by project tag, ensure that all desired resources are given a tag with the key `project` and a value of what you have named the project. 

These tags should be added at the point a resource is created. If adding tags to instances in the AWS online console, these tags will also be applied to their associated storage. However, if creating instances via CloudFormation, these must be tagged explictly (see https://aws.amazon.com/premiumsupport/knowledge-center/cloudformation-instance-tag-root-volume/). It is recommended that these project tags are added even if the intention is to track by account number, as this will allow for greater flexibility and accuracy if a second project is later added to the same account.

This application includes in its breakdown details of instances specifically used as compute nodes. For this to be measured accurately, the appropriate instances should have a tag added with the key `compute` and the value `true`. Again, these should be added at the point of creation.

The project and compute tags must also be activated in the Billing console (see https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html). It may take up to 24 hours for new tags to appear in this console.

This application makes use of a number of AWS sdks, which require a valid `Access Key ID` and `Secret Access Key`. This should relate to a user with access to: Billing and Cost Management, Cost Explorer API, EC2 API and Pricing API.

For AWS projects you also need to supply your 12 digit `AWS Account ID`, which can be found on the AWS console under 'My Security Credentials' (see https://docs.aws.amazon.com/general/latest/gr/acct-identifiers.html for details).

### Azure

In this application, Azure projects are assumed to be confined to a single Azure resource group (to be specified at project creation). In addition, it is required that compute nodes be given the `"type" => "compute"` tag on the Azure platform and core infrastructure given the `"type" => "core"` tag.

The point at which tags are added does not affect the data pulled from the Azure API. As long as the resources that you want to analyse have the tag, the detail objects associated with that resource will be queried.

In order to run the application, an app and service principal must be created in Azure Active Directory (see https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal for more details). The app must have at least `Reader` level permissions given to it in the subscription you wish to use it in, via the `Access control (IAM)` blade.

Azure projects require the following details to be obtained prior to project creation:

- Directory (tenant) ID
- Client (application) ID
- Client secret
- Subscription ID
- Resource group name(s)

The first three can be obtained via the app you created in Azure Active Directory. The subscription ID is located in the overview for the subscription containing the project; as is the resource group name in the overview for the resource group. A project may have more than one resource group, but these must be part of the same subscription.

### Slack

The application includes the option to send results to slack, specifying a specific channel for each project. To use this function, a slack bot (https://slack.com/apps/A0F7YS25R-bots) must be created. The bot's API Token should then be used to set an environment variable:

`SLACK_TOKEN=yourtoken ruby -e 'p ENV["SLACK_TOKEN"]'`

This bot must be invited to each project's chosen slack channel.

### Adding and updating projects

A `Project` object should be created for each project you wish to track. These can be created by running `ruby manage_projects.rb` and following the prompts in the command line. This file can also be used to update existing projects. Projects should not be deleted, but instead their `end_date` set to mark them as inactive.

### Adding customer friendly instance type names

An 'InstanceMapping' object can be created for adding a customer friendly name (e.g. "Compute (Large)"") for an AWS or Azure instance type (e.g. "c5.xlarge" or "Standard_F4s_v2"). These can be created by running `ruby manage_instance_mappings.rb` and following the prompts in the command line. This file can also be used to update or delete existing mappings. Customer friendly names are currently used for describing compute nodes in weekly reports. If no mapping is found for that instance type, 'Compute (other)' is used.

Some initial mappings can be generated by running `ruby db/add_instance_mappings.rb`.

### Currency and compute unit conversion

All costs are before tax. Base compute units are calculated as 10 * the GBP cost. For costs received in USD (i.e. from AWS), the default exchange rate of $1 = £0.77 is used. This can be overriden using an environment variable, replacing 0.77 with the desired, more up to date value:

 `USD_GBP_CONVERSION=new_value ruby -e 'p ENV["USD_GBP_CONVERSION"]'`

### Region name mappings

Both AWS and Azure use non standard region names in their pricing APIs/SDKs. To ensure the correct region names are used for these queries, these are mapped against instance region names in `aws_region_names.txt` and `azure_region_names.txt`. When adding resources in a new region, the related file should be checked to ensure a mapping is present.

For AWS projects, a missing mapping will be highlighted when adding regions using `update_projects.rb` and for Azure projects a missing mapping will be highlighted when generating a weekly report. At the time of writing, AWS mappings can be found at https://docs.aws.amazon.com/general/latest/gr/rande.html#ec2_region but unfortunately Azure do not publicly provide such a list.

### Timed report generation

To assist with generating reports at regular intervals, the `whenever` gem is included for automated creation of suitable crontab entries.

Firstly, `Rakefile` includes `rake` tasks for running both `daily_reports.rb` and `weekly_reports.rb`. If you wish to use these with slack, please enter your slack token at the top of `Rakefile`. These can be edited or new tasks added as needed.

The file `config/schedule.rb` is used to define when to run these tasks. The examples are set for generating daily reports every day at midday and weekly reports at midday every Monday. These can similarly be edited or added to as required. You may wish to also set an output file here using `set :output, filename.log`.

To use these tasks and timings on your system you must run `whenever --update-crontab` which will add appropriate entries to your crontab. You must run this each time you update details in `config/schedule.rb` for the changes to be reflected.

If you wish to instead manually add to your crontab, running `whenever` will print out the generated entries without updating your crontab. 

Please see https://github.com/javan/whenever for more details on using the `whenever` gem.

# Operation

The application includes functionality for generating both daily and weekly reports of cloud usage and cost data. The obtained data is saved in the database and, unless specified, queries where an existing report exists will use stored data instead of making fresh sdk/api calls.

Daily reports can be generated using `ruby daily_reports.rb`. If run without any arguments, this will iterate over all Projects in the database and retrieve data for 3 days ago (as cost & usage data takes 3 days to update). The results will be printed to the terminal and posted to the chosen slack channel(s).

Weekly reports can similarly be generated using `ruby weekly_reports.rb`. If run without any arguments, this will iterate over all Projects in the database and retrieve data for the month so far, including estimating costs for the rest of the month. The results will be printed to the terminal and posted to the chosen slack channel(s). Weekly reports use the specified date (3 days ago by default) for historical cost data, and will use either use the specified date's instance information, or today's if generating the 'latest' report.

Weekly reports take up to 7 arguments and daily reports up to 8:

1: project name or 'all'\
2: a specific date or 'latest'. All dates must be in the format YYYY-MM-DD

The following are optional and unordered (but must be at least the third argument):

3: 'slack' will post the results to the chosen slack channel(s)\
4: 'text' will print out the results. If no output method is specified (neither 'text' or 'slack'), results will be posted to slack and printed on the terminal\
5: 'rerun' will ignore cached reports and regenerate them with fresh SDK/API calls\
6: 'verbose' will expand any brief Azure API or AWS SDK errors to include the full error.\
7: 'customer' or 'internal' will show customer facing or true instance names respectively. If not specified, by default daily reports will show true names and weekly reports customer facing names. For weekly reports this argument will not alter a cached report (which is stored as text), so if used for a previously generated weekly report, must also include the argument 'rerun'. Daily reports are stored as their component parts, so these names can be altered without a rerun.\
8: 'short' (daily reports only) will ouptut a shortened report, that does not show compute unit costs for compute or data out costs, does not show data out amount and does not show details of instances on the given date.


## Examples

To get all projects' reports with cost data from three days ago, with both slack and text output, using cached data if present:

`ruby daily_reports.rb` or `ruby daily_reports.rb all latest`

`ruby weekly_reports.rb` or `ruby weekly_reports.rb all latest`

To get a report for a specific project, with cost data from three days ago, with only text output and using cached data if present:

`ruby daily_reports.rb projectName latest text`

`ruby weekly_reports.rb projectName latest text`

To get a report for a specific project, with cost data from three days ago, with only slack output and using cached data if present:

`ruby daily_reports.rb projectName latest slack`

`ruby weekly_reports.rb projectName latest slack`

To get a report for a specific project for a specific date, with both slack and text output and using cached data if present:

`ruby daily_reports.rb projectName 2020-09-20 slack text`

`ruby weekly_reports.rb projectName 2020-09-20 slack text`

To get all projects' reports for a specific day, with only text output and fresh cost and usage queries:

`ruby daily_reports.rb all 2020-09-20 text rerun`

`ruby weekly_reports.rb all 2020-09-20 text rerun`

To get all projects' daily reports for a specific day, with only text output and customer facing instance names:

`ruby daily_reports.rb all 2020-09-20 text customer`

To get all projects' weekly reports for a specific day, with only text output, true instance names and fresh cost and usage queries:

`ruby weekly_reports.rb all 2020-09-20 text internal rerun `

To get all projects' daily reports for a specific day, with only text output, customer facing instance names, fresh cost and usage queries and with shortened output:

`ruby weekly_reports.rb all 2020-09-20 text internal rerun short`


### Recording Azure Pricing

For the weekly report, future costs are estimated based on the active compute nodes and their daily costs, using pricing from AWS and Azure respectively. For Azure, the Ratecard api used here returns a very large list of prices, with extremely limited serverside filtering available. To prevent excessive waits for this request each time `weekly_reports.rb` is run, this price list is saved to a text file, `azure_prices.txt`. This includes a timestamp, and when generating Azure weekly reports, if less than a day old, the data is read directly from the file rather than making another api request.

You can also run `ruby get_latest_azure_prices.rb`, which will use an existing Azure project (which provides the required credentials for the API) to run this update to the prices on command. By setting up a cronjob to run this separately from the main files (for example, at the start of each day), wait times for generating Azure weekly reports can be dramatically reduced.

### Recording Azure Instance Details and AWS Instance Details & Pricing

The application also includes initial versions of the files `aws_instance_details.txt` and `azure_instance_sizes.txt`. The latter is not required for this application, but both are used by the associated openflight `cloud-cost-visualiser` project, with the files generated here as they require a valid AWS / Azure project for retrieving the data. These can be updated by runing `ruby get_latest_aws_instance_info` and `ruby get_latest_azure_instance_sizes.rb` respectively. `aws_instance_details.txt` is also updated when generating a weekly report for an AWS project (if the existing file is not already up to date).

### Recording historic cost logs

If a project has significant gaps in its cost and usage logs, for example due to only recently being added to this application, two helpers are provided to fill these gaps without the need for manually running daily reports for each missing day.

Firstly, `record_logs.rb` can be run, with three required arguments and one optional argument. These are, in order: the project name, start date, end date and rerun (optional). This will query the relevant AWS SDKs / Azure APIs and record cost and usage logs for all days in that date range (inclusive). For example `ruby record_logs.rb project1 2020-01-01 2020-09-30` will record logs for the project named project1 for all days between and including 1st January 2020 to 30th September.

If the 4th, optional argument `rerun` is not included, this will ignore any dates which already have logs recorded. If it is included, any existing logs will be overwritten with newly retrieved data.

Historic gaps can also be filled when adding a project using `manage_projects.rb`. Here, if the project has a start date in the past, after the project is created the user is asked if they want to retrieve historic data. Entering `y` will carry out the same process as in `record_logs.rb`, for all dates from the project start date to 3 days ago (the latest date cost data is available).

For AWS projects this retrieval and recording is a quick process, even with a large date range (300+ days). However, due to limitations in possible queries to Azure APIs and their slow responses, this can take 5+ minutes per 1 month of data for Azure Projects.

Please note that compute costs are only available for dates after compute tags have been added to resources. For Azure projects, historic compute costs will be available only for instances that have previously been identified and recorded as compute instances in instance logs.

# Contributing

Fork the project. Make your feature addition or bug fix. Send a pull
request. Bonus points for topic branches.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

# Copyright and License

Eclipse Public License 2.0, see [LICENSE.txt](LICENSE.txt) for details.

Copyright (C) 2020-present Alces Flight Ltd.

This program and the accompanying materials are made available under
the terms of the Eclipse Public License 2.0 which is available at
[https://www.eclipse.org/legal/epl-2.0](https://www.eclipse.org/legal/epl-2.0),
or alternative license terms made available by Alces Flight Ltd -
please direct inquiries about licensing to
[licensing@alces-flight.com](mailto:licensing@alces-flight.com).

ruby-cost-tracker is distributed in the hope that it will be
useful, but WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER
EXPRESS OR IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR
CONDITIONS OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR
A PARTICULAR PURPOSE. See the [Eclipse Public License 2.0](https://opensource.org/licenses/EPL-2.0) for more
details.
