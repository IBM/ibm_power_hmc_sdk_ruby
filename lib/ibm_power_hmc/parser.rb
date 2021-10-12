# frozen_string_literal: true

require 'time'
require 'uri'

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  # Parser for HMC feeds and entries.
  class Parser
    def initialize(body)
      @doc = REXML::Document.new(body)
    end

    def entry
      @doc.elements["entry"]
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
  end

  # HMC generic XML entry
  class AbstractRest
    attr_reader :uuid, :published, :xml

    def initialize(doc, type)
      @uuid = doc.elements["id"]&.text
      @published = Time.xmlschema(doc.elements["published"]&.text)
      @xml = doc.elements["content/#{type}:#{type}"]
    end

    def define_attr(varname, xpath)
      value = xml.elements[xpath]&.text&.strip
      self.class.__send__(:attr_reader, varname)
      instance_variable_set("@#{varname}", value)
    end

    def define_attrs(hash)
      hash.each do |key, value|
        define_attr(key, value)
      end
    end

    def extract_uuid_from_href(href)
      URI(href).path.split('/').last
    end
  end

  # HMC information
  class ManagementConsole < AbstractRest
    XMLMAP = {
      :name => "ManagementConsoleName",
      :build_level => "VersionInfo/BuildLevel",
      :version => "BaseVersion"
    }.freeze

    def initialize(doc)
      super(doc, :ManagementConsole)
      define_attrs(XMLMAP)
    end

    def managed_systems_uuids
      uuids = []
      xml.each_element("ManagedSystems/link") do |link|
        uuids << extract_uuid_from_href(link.attributes["href"])
      end
      uuids.compact
    end
  end

  # Managed System information
  class ManagedSystem < AbstractRest
    XMLMAP = {
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

    def initialize(doc)
      super(doc, :ManagedSystem)
      define_attrs(XMLMAP)
    end

    def lpars_uuids
      uuids = []
      xml.each_element("AssociatedLogicalPartitions/link") do |link|
        uuids << extract_uuid_from_href(link.attributes["href"])
      end
      uuids.compact
    end

    def vioses_uuids
      uuids = []
      xml.each_element("AssociatedVirtualIOServers/link") do |link|
        uuids << extract_uuid_from_href(link.attributes["href"])
      end
      uuids.compact
    end
  end

  # Common class for LPAR and VIOS
  class BasePartition < AbstractRest
    XMLMAP = {
      :name => "PartitionName",
      :id => "PartitionID",
      :state => "PartitionState",
      :type => "PartitionType",
      :memory => "PartitionMemoryConfiguration/CurrentMemory",
      :dedicated => "PartitionProcessorConfiguration/HasDedicatedProcessors",
      :rmc_state => "ResourceMonitoringControlState",
      :rmc_ipaddr => "ResourceMonitoringIPAddress"
    }.freeze

    def initialize(doc, type)
      super(doc, type)
      define_attrs(XMLMAP)
    end

    def sys_uuid
      sys_href = xml.elements["AssociatedManagedSystem"].attributes["href"]
      extract_uuid_from_href(sys_href)
    end
  end

  # Logical Partition information
  class LogicalPartition < BasePartition
    def initialize(doc)
      super(doc, :LogicalPartition)
    end
  end

  # VIOS information
  class VirtualIOServer < BasePartition
    def initialize(doc)
      super(doc, :VirtualIOServer)
    end
  end

  # HMC Event
  class Event < AbstractRest
    XMLMAP = {
      :id     => "EventID",
      :type   => "EventType",
      :data   => "EventData",
      :detail => "EventDetail"
    }.freeze

    def initialize(doc)
      super(doc, :Event)
      define_attrs(XMLMAP)
    end
  end

  # Error response from HMC
  class HttpErrorResponse < AbstractRest
    XMLMAP = {
      :status  => "HTTPStatus",
      :uri     => "RequestURI",
      :reason  => "ReasonCode",
      :message => "Message"
    }.freeze

    def initialize(doc)
      super(doc, :HttpErrorResponse)
      define_attrs(XMLMAP)
    end
  end
end
