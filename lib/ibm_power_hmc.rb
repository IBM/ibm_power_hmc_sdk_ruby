# frozen_string_literal: true

require "rexml/document"
require "rest-client"

require "ibm_power_hmc/version"

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  require_relative "./ibm_power_hmc/apis/connection"
  require_relative "./ibm_power_hmc/apis/job"
  require_relative "./ibm_power_hmc/apis/pcm"
  require_relative "./ibm_power_hmc/apis/sem"
  require_relative "./ibm_power_hmc/apis/templates"
  require_relative "./ibm_power_hmc/apis/uom"
  require_relative "./ibm_power_hmc/schema/parser"
  require_relative "./ibm_power_hmc/schema/pcm"
  require_relative "./ibm_power_hmc/schema/sem"
  require_relative "./ibm_power_hmc/schema/templates"
  require_relative "./ibm_power_hmc/schema/uom"
end
