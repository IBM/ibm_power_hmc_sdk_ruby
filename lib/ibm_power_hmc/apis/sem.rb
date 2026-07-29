# frozen_string_literal: true

##
# Serviceable Events Manager.

module IbmPowerHmc
  class Connection
    ##
    # @!method serviceable_events(status = nil)
    # Retrieve serviceable events from the HMC.
    # @param status [String] Query only events in that state.
    # @return [Array<IbmPowerHmc::ServiceableEvent>] The list of serviceable events.
    def serviceable_events(status = nil)
      method_url = "/rest/api/sem/ServiceableEvent"
      method_url += "?status=#{status}" unless status.nil?
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:ServiceableEvent)
    end

    ##
    # @!method serviceable_events_search
    # Retrieve all serviceable events using the search/hmc=all endpoint.
    # Returns the raw XML response body as a String so callers can transform
    # or persist it as needed.
    # @return [String] Raw XML response body from the HMC.
    def serviceable_events_search(query = { hmc: 'all' })
      search_params = query.map { |key, value| "#{key}=#{value}" }.join('/')
      response = request(:get, "/rest/api/sem/ServiceableEvent/search/#{search_params}")
      response.body.to_s
    end
  end
end
