# ruby-cost-tracker

Tracker tool for Azure and AWS costs.

## Overview

A proof of concept application for tracking Azure and AWS costs and usage. Built in Ruby (no framework), with a basic SQLite database.

## Installation

This application requires Ruby (2.5.1) and a recent version of Bundler (2.1.4).

After downloading the source code (via git or other means), the gems need to be installed using bundler:

```
cd /path/to/source
bundle install
```

To create the local database, run `db/setup.rb`.

## Configuration

### AWS 

On AWS, projects can be tracked on an account or project tag level. For tracking by project tag, ensure that all desired resources are given a tag with the key `project` and a value of what you have named the project. 

These tags should be added at the point a resource is created. If adding tags to instances in the AWS online console, these tags will also be applied to their associated storage. However, if creating instances via CloudFormation, these must be tagged explictly (see https://aws.amazon.com/premiumsupport/knowledge-center/cloudformation-instance-tag-root-volume/). It is recommended that these project tags are added even if the intention is to track by account number, as this will allow for greater flexibility and accuracy if a second project is later added to the same account.

This application includes in its breakdown details of instances specifically used as compute nodes. For this to be measured accurately, the appropriate instances should have a tag added with the key `compute` and the value `true`. Again, these should be added at the point of creation.

The project and compute tags must also be activated in the Billing console (see https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html).

This application makes use of a number of AWS sdks, which require a valid `Access Key ID` and `Secret Access Key`. This should relate to a user with access to: Billing and Cost Management, Cost Explorer API, EC2 API and Pricing API.

### Azure

In this application, Azure projects are assumed to be confined to a single Azure resource group (to be specified at project creation). In addition, it is required that compute nodes be given the `"type" => "compute"` tag on the Azure platform.

The point at which tags are added does not affect the data pulled from the Azure API. As long as the resources that you want to analyse have the tag, the detail objects associated with that resource will be queried.

Azure projects require the following details to be obtained prior to project creation:

- Directory (tenant) ID
- Client (application) ID
- Client secret
- Subscription ID
- Resource group name

The first three can be obtained via the app you created in Azure Active Directory (see https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal for more details). The subscription ID is located in the overview for the subscription containing the project; as is the resource group name in the overview for the resource group.


### Slack

The application includes the option to send results to slack, specifying a specific channel for each project. To use this function, a slack bot (https://slack.com/apps/A0F7YS25R-bots) must be created. The bot's API Token should then be used to set an environment variable:

`API_KEY=yourtoken ruby -e 'p ENV["API_KEY"]'`

This bot must be invited to each project's chosen slack channel.

### Adding projects

A `Project` object should be created for each project you wish to track. These can be created by running `ruby manage_projects.rb` and following the prompts in the command line. This file can also be used to update existing projects.

# Operation

The application includes functionality for generating both daily (AWS and Azure) and weekly (AWS) reports of cloud usage and cost data. The obtained data is saved in the database and, unless specified, queries where an existing report exists will use stored data instead of making fresh sdk/api calls.

Daily reports can be generated using `ruby get_all_costs_and_usage.rb`. If run without any arguments, this will iterate over all Projects in the database and retrieve data for 2 days ago (as cost & usage data takes 2 days to update). The results will be printed to the terminal and posted to the chosen slack channel(s).

Weekly reports can similarly be generated using `ruby weekly_reports.rb`. If run without any arguments, this will iterate over all Projects in the database and retrieve data for the month so far, including estimating costs for the rest of the month. The results will be printed to the terminal and posted to the chosen slack channel(s). Weekly reports use the specified date (2 days ago by default) for historical cost data, but will use today's instance and pricing data for estimating future costs.

Both of these files also take up to 4 arguments:

1: project name or 'all'\
2: a specific date or 'latest'. All dates must be in the format YYYY-MM-DD\
3 (optional & unordered): 'slack' or 'text'. If text no message will be sent to slack\
4 (optional & unordered): 'rerun' will ignore cached reports and regenerate them with fresh sdk/ api calls\

For example 'ruby get_all_costs_and_usage.rb project1 2020-09-01 rerun' will generate the report for a project called 'project1', with data from the 1st September 2020, using fresh sdk/api calls, posting to slack and printing to the terminal.

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
