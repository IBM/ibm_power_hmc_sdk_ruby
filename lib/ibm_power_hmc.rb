# frozen_string_literal: true

require "rexml/document"
require "rest-client"

require "ibm_power_hmc/version"

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  require_relative "./ibm_power_hmc/objects.rb"
  require_relative "./ibm_power_hmc/job.rb"
  require_relative "./ibm_power_hmc/connection.rb"
end
