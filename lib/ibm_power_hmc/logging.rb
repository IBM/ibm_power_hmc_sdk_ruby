# frozen_string_literal: true

require "ibm_power_hmc/null_logger"

module IbmPowerHmc
  class << self
    attr_writer :logger
  end

  def self.logger
    @logger ||= NullLogger.new
  end

  module Logging
    def logger
      IbmPowerHmc.logger
    end
  end
end
