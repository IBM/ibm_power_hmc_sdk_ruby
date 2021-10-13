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
    ATTRS = {}.freeze
    attr_reader :uuid, :published, :xml

    def initialize(doc)
      @uuid = doc.elements["id"]&.text
      @published = Time.xmlschema(doc.elements["published"]&.text)
      type = self.class.name.split("::").last
      @xml = doc.elements["content/#{type}:#{type}"]
      define_attrs(self.class::ATTRS)
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
      :name => "PartitionName",
      :id => "PartitionID",
      :state => "PartitionState",
      :type => "PartitionType",
      :memory => "PartitionMemoryConfiguration/CurrentMemory",
      :dedicated => "PartitionProcessorConfiguration/HasDedicatedProcessors",
      :rmc_state => "ResourceMonitoringControlState",
      :rmc_ipaddr => "ResourceMonitoringIPAddress"
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
end
