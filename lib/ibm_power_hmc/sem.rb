# frozen_string_literal: true

# Serviceable Events Manager

module IbmPowerHmc
  class Connection
    ##
    # @!method serviceable_events
    # Retrieve serviceable events from the HMC.
    # @param status [String] Query only events in that state.
    # @return [Array<IbmPowerHmc::ServiceableEvent>] The list of serviceable events.
    def serviceable_events(status = nil)
      method_url = "/rest/api/sem/ServiceableEvent"
      method_url += "?status=#{status}" unless status.nil?
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:ServiceableEvent)
    end
  end
end
