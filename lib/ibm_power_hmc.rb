# frozen_string_literal: true

require "rexml/document"
require "rest-client"

require "ibm_power_hmc/version"

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  require_relative "./ibm_power_hmc/parser"
  require_relative "./ibm_power_hmc/job"
  require_relative "./ibm_power_hmc/connection"
  require_relative "./ibm_power_hmc/pcm"
  require_relative "./ibm_power_hmc/sem"
  require_relative "./ibm_power_hmc/templates"
  require_relative "./ibm_power_hmc/uom"
end
