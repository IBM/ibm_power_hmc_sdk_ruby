# frozen_string_literal: true

require "rexml/document"
require "rest-client"

require "ibm_power_hmc/version"

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  require_relative "./ibm_power_hmc/objects"
  require_relative "./ibm_power_hmc/job"
  require_relative "./ibm_power_hmc/connection"
  require_relative "./ibm_power_hmc/pcm"
end
