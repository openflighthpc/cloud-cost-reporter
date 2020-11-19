#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
#
# This file is part of cloud-cost-reporter.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# cloud-cost-reporter is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with cloud-cost-reporter. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on cloud-cost-reporter, please visit:
# https://github.com/openflighthpc/cloud-cost-reporter
#==============================================================================

require 'sqlite3'
load './models/instance_mapping.rb'

InstanceMapping.create(instance_type: "t3.medium", customer_facing_name: "General (Small)")
InstanceMapping.create(instance_type: "t3.xlarge", customer_facing_name: "General (Medium)")
InstanceMapping.create(instance_type: "t3.2xlarge", customer_facing_name: "General (Large)")
InstanceMapping.create(instance_type: "c5.large", customer_facing_name: "Compute (Small)")
InstanceMapping.create(instance_type: "c5.xlarge", customer_facing_name: "Compute (Medium)")
InstanceMapping.create(instance_type: "c5.2xlarge", customer_facing_name: "Compute (Large)")
InstanceMapping.create(instance_type: "p3.2xlarge", customer_facing_name: "GPU (Small)")
InstanceMapping.create(instance_type: "p3.8xlarge", customer_facing_name: "GPU (Medium)")
InstanceMapping.create(instance_type: "p3.16xlarge", customer_facing_name: "GPU (Large)")
InstanceMapping.create(instance_type: "r5.large", customer_facing_name: "Mem (Small)")
InstanceMapping.create(instance_type: "r5.xlarge", customer_facing_name: "Mem (Medium)")
InstanceMapping.create(instance_type: "r5.2xlarge", customer_facing_name: "Mem (Large)")
InstanceMapping.create(instance_type: "Standard_F2s_v2", customer_facing_name: "Compute (Small)")
InstanceMapping.create(instance_type: "Standard_F4s_v2", customer_facing_name: "Compute (Medium)")
InstanceMapping.create(instance_type: "Standard_F8s_v2", customer_facing_name: "Compute (Large)")
InstanceMapping.create(instance_type: "Standard_NC6s_v3", customer_facing_name: "GPU (Small)")
InstanceMapping.create(instance_type: "Standard_NC24s_v3", customer_facing_name: "GPU (Medium)")
InstanceMapping.create(instance_type: "Standard_E2_v4", customer_facing_name: "Mem (Small)")
InstanceMapping.create(instance_type: "Standard_E4_v4", customer_facing_name: "Mem (Medium)")
InstanceMapping.create(instance_type: "Standard_E8_v4", customer_facing_name: "Mem (Large)")
InstanceMapping.create(instance_type: "Standard_B2s", customer_facing_name: "General (Small)")