require 'sqlite3'
load './models/instance_mapping.rb'

InstanceMapping.create(instance_type: "c5.large", customer_facing_name: "Compute (Small)")
InstanceMapping.create(instance_type: "c5.xlarge", customer_facing_name: "Compute (Medium)")
InstanceMapping.create(instance_type: "c5.2xlarge", customer_facing_name: "Compute (Large)")
InstanceMapping.create(instance_type: "p3.2xlarge", customer_facing_name: "GPU (Small)")
InstanceMapping.create(instance_type: "p3.8xlarge", customer_facing_name: "GPU (Medium)")
InstanceMapping.create(instance_type: "p3.16xlarge", customer_facing_name: "GPU (Large)")
InstanceMapping.create(instance_type: "r5.large", customer_facing_name: "Mem (Small)")
InstanceMapping.create(instance_type: "r5.xlarge", customer_facing_name: "Mem (Medium)")
InstanceMapping.create(instance_type: "r5.2xlarge", customer_facing_name: "Mem (Large)")
