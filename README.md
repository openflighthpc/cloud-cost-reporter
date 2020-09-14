# ruby-cost-tracker

An initial conversion of https://github.com/openflighthpc/aws_cost_utils into a Ruby project.

This is regular Ruby (no framework), with a basic SQLite database.

A Project object should be created for each cloud cluster (in irb or a script), containing details such as if AWS or Azure (not yet supported), access credentials 
and what slack channel results should be sent to.

By running `ruby get_all_costs_and_usage.rb` all Projects are iterated through and their overall spend and usage on EC2 instances retrieved for 2 days ago. 
Results are sent to the relevant slack channel via 'timbot', or a bot of your choice.

At the moment this does not include a snapshot of instances alive at the point run, but does show total hours for each instance type.

As an experimental addition to the original aws_cost_utils project, this also retrieves the forecast cost and overall run hours for today, again posting these to the relevant slack channel.

# Setup

- Run `bundle install` to install gems
- Run `db/setup.rb` to create your local database
- Run `irb` and create project(s) for testing (see db/setup for fields)
