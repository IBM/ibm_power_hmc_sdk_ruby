# frozen_string_literal: true

require 'json'
require 'uri'

module IbmPowerHmc
  class Connection
    ##
    # @!method managed_system_metrics(sys_uuid:, start_ts: nil, end_ts: nil, no_samples: nil)
    # Retrieve metrics for a managed system.
    # @param sys_uuid [String] The managed system UUID.
    # @param start_ts [String] Start timestamp.
    # @param end_ts [String] End timestamp.
    # @param no_samples [Integer] Number of samples.
    # @return [Array<Hash>] The processed metrics for the managed system.
    def managed_system_metrics(sys_uuid:, start_ts: nil, end_ts: nil, no_samples: nil)
      method_url = "/rest/api/pcm/ManagedSystem/#{sys_uuid}/ProcessedMetrics"
      query = []
      query << "StartTS=#{start_ts}" unless start_ts.nil?
      query << "EndTS=#{end_ts}" unless end_ts.nil?
      query << "NoOfSamples=#{no_samples}" unless no_samples.nil?
      method_url += "?" + query.compact.join('&') unless query.empty?

      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      metrics = []
      doc.each_element("feed/entry") do |entry|
        category = entry.elements["category"]
        next if category.nil?

        term = category.attributes["term"]
        next if term.nil? || term != "ManagedSystem"

        link = entry.elements["link"]
        next if link.nil?

        href = link.attributes["href"]
        next if href.nil?

        response = request(:get, href.to_s)
        metrics << JSON.parse(response.body)
      end
      metrics
    end
  end
end
