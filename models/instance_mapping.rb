require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'db/cost_tracker.sqlite3')

class InstanceMapping < ActiveRecord::Base
  validates :instance_type, uniqueness: true
end
