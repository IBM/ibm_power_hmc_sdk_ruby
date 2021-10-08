# frozen_string_literal: true

require 'json'
require 'uri'

module IbmPowerHmc
  class Connection
    def pcm_preferences
      method_url = "/rest/api/pcm/preferences"

      response = request(:get, method_url)
      REXML::Document.new(response.body)
    end

    ##
    # @!method phyp_metrics(sys_uuid:, start_ts: nil, end_ts: nil, short_term: false)
    # Retrieve PowerVM metrics for a given managed system.
    # @param sys_uuid [String] The managed system UUID.
    # @param start_ts [Time] Start timestamp.
    # @param end_ts [Time] End timestamp.
    # @param short_term [Boolean] Retrieve short term monitor metrics (default to long term).
    # @return [Array<Hash>] The PowerVM metrics for the managed system.
    def phyp_metrics(sys_uuid:, start_ts: nil, end_ts: nil, short_term: false)
      type = short_term ? "ShortTermMonitor" : "LongTermMonitor"
      method_url = "/rest/api/pcm/ManagedSystem/#{sys_uuid}/RawMetrics/#{type}"
      query = {}
      query["StartTS"] = self.class.format_time(start_ts) unless start_ts.nil?
      query["EndTS"] = self.class.format_time(end_ts) unless end_ts.nil?
      method_url += "?" + query.map { |h| h.join("=") }.join("&") unless query.empty?

      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      metrics = []
      doc.each_element("feed/entry") do |entry|
        href = entry.elements["link"]&.attributes["href"]
        next if href.nil?

        response = request(:get, href)
        metrics << JSON.parse(response.body)
      end
      metrics
    end

    ##
    # @!method managed_system_metrics(sys_uuid:, start_ts: nil, end_ts: nil, no_samples: nil, aggregated: false)
    # Retrieve metrics for a managed system.
    # @param sys_uuid [String] The managed system UUID.
    # @param start_ts [Time] Start timestamp.
    # @param end_ts [Time] End timestamp.
    # @param no_samples [Integer] Number of samples.
    # @param aggregated [Boolean] Retrieve aggregated metrics (default to Processed).
    # @return [Array<Hash>] The metrics for the managed system.
    def managed_system_metrics(sys_uuid:, start_ts: nil, end_ts: nil, no_samples: nil, aggregated: false)
      type = aggregated ? "AggregatedMetrics" : "ProcessedMetrics"
      method_url = "/rest/api/pcm/ManagedSystem/#{sys_uuid}/#{type}"
      query = {}
      query["StartTS"] = self.class.format_time(start_ts) unless start_ts.nil?
      query["EndTS"] = self.class.format_time(end_ts) unless end_ts.nil?
      query["NoOfSamples"] = no_samples unless no_samples.nil?
      method_url += "?" + query.map { |h| h.join("=") }.join("&") unless query.empty?

      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      metrics = []
      doc.each_element("feed/entry") do |entry|
        term = entry.elements["category"]&.attributes["term"]
        next if term.nil? || term != "ManagedSystem"

        href = entry.elements["link"]&.attributes["href"]
        next if href.nil?

        response = request(:get, href)
        metrics << JSON.parse(response.body)
      end
      metrics
    end

    ##
    # @!method lpar_metrics(sys_uuid:, lpar_uuid:, start_ts: nil, end_ts: nil, no_samples: nil, aggregated: false)
    # Retrieve metrics for a logical partition.
    # @param sys_uuid [String] The managed system UUID.
    # @param lpar_uuid [String] The logical partition UUID.
    # @param start_ts [Time] Start timestamp.
    # @param end_ts [Time] End timestamp.
    # @param no_samples [Integer] Number of samples.
    # @param aggregated [Boolean] Retrieve aggregated metrics (default to Processed).
    # @return [Array<Hash>] The metrics for the logical partition.
    def lpar_metrics(sys_uuid:, lpar_uuid:, start_ts: nil, end_ts: nil, no_samples: nil, aggregated: false)
      type = aggregated ? "AggregatedMetrics" : "ProcessedMetrics"
      method_url = "/rest/api/pcm/ManagedSystem/#{sys_uuid}/LogicalPartition/#{lpar_uuid}/#{type}"
      query = {}
      query["StartTS"] = self.class.format_time(start_ts) unless start_ts.nil?
      query["EndTS"] = self.class.format_time(end_ts) unless end_ts.nil?
      query["NoOfSamples"] = no_samples unless no_samples.nil?
      method_url += "?" + query.map { |h| h.join("=") }.join("&") unless query.empty?

      response = request(:get, method_url)
      doc = REXML::Document.new(response.body)
      metrics = []
      doc.each_element("feed/entry") do |entry|
        href = entry.elements["link"]&.attributes["href"]
        next if href.nil?

        response = request(:get, href)
        metrics << JSON.parse(response.body)
      end
      metrics
    end

    ##
    # @!method format_time(time)
    # Convert ruby time to HMC time format.
    # @param time [Time] The ruby time to convert.
    # @return [String] The time in HMC format.
    def self.format_time(time)
      time.utc.xmlschema
    end
  end
end
