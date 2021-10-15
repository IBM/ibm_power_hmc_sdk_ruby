# frozen_string_literal: true

require 'time'
require 'uri'

module IbmPowerHmc
  # Parser for HMC feeds and entries.
  class Parser
    def initialize(body)
      @doc = REXML::Document.new(body)
    end

    def entry
      @doc.elements["entry"]
    end

    def object(filter_type = nil)
      self.class.to_obj(entry, filter_type)
    end

    def self.to_obj(entry, filter_type = nil)
      return if entry.nil?

      content = entry.elements["content"]
      return if content.nil?

      type = content.attributes["type"]
      return if type.nil?

      type = type.split("=").last
      return unless filter_type.nil? || filter_type.to_s == type

      Module.const_get("IbmPowerHmc::#{type}").new(entry)
    end
  end

  class FeedParser < Parser
    def entries
      objs = []
      @doc.each_element("feed/entry") do |entry|
        objs << yield(entry)
      end
      objs
    end

    def objects(filter_type = nil)
      entries do |entry|
        self.class.to_obj(entry, filter_type)
      end.compact
    end
  end

  private_constant :Parser
  private_constant :FeedParser

  # HMC generic XML entry
  class AbstractRest
    ATTRS = {}.freeze
    attr_reader :uuid, :published, :etag, :xml

    def initialize(doc)
      @uuid = doc.elements["id"]&.text
      @published = Time.xmlschema(doc.elements["published"]&.text)
      @etag = doc.elements["etag:etag"]&.text&.strip
      type = self.class.name.split("::").last
      @xml = doc.elements["content/#{type}:#{type}"]
      define_attrs(self.class::ATTRS)
    end

    def define_attr(varname, xpath)
      value = text_element(xpath)
      self.class.__send__(:attr_reader, varname)
      instance_variable_set("@#{varname}", value)
    end

    def define_attrs(hash)
      hash.each do |key, value|
        define_attr(key, value)
      end
    end

    def text_element(xpath)
      xml.elements[xpath]&.text&.strip
    end

    def extract_uuid_from_href(href)
      URI(href).path.split('/').last
    end
  end

  # HMC information
  class ManagementConsole < AbstractRest
    ATTRS = {
      :name => "ManagementConsoleName",
      :build_level => "VersionInfo/BuildLevel",
      :version => "BaseVersion"
    }.freeze

    def managed_systems_uuids
      xml.get_elements("ManagedSystems/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end
  end

  # Managed System information
  class ManagedSystem < AbstractRest
    ATTRS = {
      :name => "SystemName",
      :state => "State",
      :hostname => "Hostname",
      :ipaddr => "PrimaryIPAddress",
      :fwversion => "SystemFirmware",
      :memory => "AssociatedSystemMemoryConfiguration/InstalledSystemMemory",
      :avail_mem => "AssociatedSystemMemoryConfiguration/CurrentAvailableSystemMemory",
      :cpus => "AssociatedSystemProcessorConfiguration/InstalledSystemProcessorUnits",
      :avail_cpus => "AssociatedSystemProcessorConfiguration/CurrentAvailableSystemProcessorUnits",
      :mtype => "MachineTypeModelAndSerialNumber/MachineType",
      :model => "MachineTypeModelAndSerialNumber/Model",
      :serial => "MachineTypeModelAndSerialNumber/SerialNumber"
    }.freeze

    def lpars_uuids
      xml.get_elements("AssociatedLogicalPartitions/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end

    def vioses_uuids
      xml.get_elements("AssociatedVirtualIOServers/link").map do |link|
        extract_uuid_from_href(link.attributes["href"])
      end.compact
    end
  end

  # Common class for LPAR and VIOS
  class BasePartition < AbstractRest
    ATTRS = {
      :os => "OperatingSystemVersion",
      :name => "PartitionName",
      :id => "PartitionID",
      :state => "PartitionState",
      :type => "PartitionType",
      :memory => "PartitionMemoryConfiguration/CurrentMemory",
      :dedicated => "PartitionProcessorConfiguration/HasDedicatedProcessors",
      :rmc_state => "ResourceMonitoringControlState",
      :rmc_ipaddr => "ResourceMonitoringIPAddress",
      :ref_code => "ReferenceCode"
    }.freeze

    def sys_uuid
      sys_href = xml.elements["AssociatedManagedSystem"].attributes["href"]
      extract_uuid_from_href(sys_href)
    end
  end

  # Logical Partition information
  class LogicalPartition < BasePartition
  end

  # VIOS information
  class VirtualIOServer < BasePartition
  end

  # VirtualSwitch information
  class VirtualSwitch < HmcObject
    attr_reader :sys_uuid

    XMLMAP = {
      "SwitchID" => "id",
      "SwitchMode" => "mode",
      "SwitchName" => "name"
    }.freeze

    def initialize(doc)
      super(doc)
      sys_href = doc.elements["link[@rel='SELF']"].attributes["href"]
      @sys_uuid = URI(sys_href).path.split('/')[-3]
      info = doc.elements["content/VirtualSwitch:VirtualSwitch"]
      get_values(info, XMLMAP)
    end

    def to_s
      "id = #{@id} mode = #{@mode} name = #{@name}"
    end
  end


  # HMC Event
  class Event < AbstractRest
    ATTRS = {
      :id     => "EventID",
      :type   => "EventType",
      :data   => "EventData",
      :detail => "EventDetail"
    }.freeze
  end

  # Error response from HMC
  class HttpErrorResponse < AbstractRest
    ATTRS = {
      :status  => "HTTPStatus",
      :uri     => "RequestURI",
      :reason  => "ReasonCode",
      :message => "Message"
    }.freeze
  end

  # Job Response
  class JobResponse < AbstractRest
    ATTRS = {
      :id      => "JobID",
      :status  => "Status",
      :message => "ResponseException/Message"
    }.freeze

    def results
      results = {}
      xml.each_element("Results/JobParameter") do |result|
        name = result.elements["ParameterName"]&.text&.strip
        value = result.elements["ParameterValue"]&.text&.strip
        results[name] = value unless name.nil?
      end
      results
    end
  end
end
