require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class UsageLog < ActiveRecord::Base
  belongs_to :project
end
