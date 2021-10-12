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

    def initialize(doc)
      @uuid = doc.elements["id"]&.text
      @published = Time.xmlschema(doc.elements["published"]&.text)
      @xml = doc
    end

    def get_value(doc, xpath, varname)
      value = doc.elements[xpath]&.text&.strip
      self.class.__send__(:attr_reader, varname)
      instance_variable_set("@#{varname}", value)
    end

    def get_values(doc, hash)
      hash.each do |key, value|
        get_value(doc, key, value)
      end
    end
  end

  # HMC information
  class ManagementConsole < AbstractRest
    XMLMAP = {
      "ManagementConsoleName" => "name",
      "VersionInfo/BuildLevel" => "build_level",
      "BaseVersion" => "version"
    }.freeze

    def initialize(doc)
      super(doc)
      info = doc.elements["content/ManagementConsole:ManagementConsole"]
      get_values(info, XMLMAP)
    end
  end

  # Managed System information
  class ManagedSystem < AbstractRest
    XMLMAP = {
      "SystemName" => "name",
      "State" => "state",
      "Hostname" => "hostname",
      "PrimaryIPAddress" => "ipaddr",
      "SystemFirmware" => "fwversion",
      "AssociatedSystemMemoryConfiguration/InstalledSystemMemory" => "memory",
      "AssociatedSystemMemoryConfiguration/CurrentAvailableSystemMemory" => "avail_mem",
      "AssociatedSystemProcessorConfiguration/InstalledSystemProcessorUnits" => "cpus",
      "AssociatedSystemProcessorConfiguration/CurrentAvailableSystemProcessorUnits" => "avail_cpus",
      "MachineTypeModelAndSerialNumber/MachineType" => "mtype",
      "MachineTypeModelAndSerialNumber/Model" => "model",
      "MachineTypeModelAndSerialNumber/SerialNumber" => "serial",
    }.freeze

    def initialize(doc)
      super(doc)
      info = doc.elements["content/ManagedSystem:ManagedSystem"]
      get_values(info, XMLMAP)
    end
  end

  # Common class for LPAR and VIOS
  class BasePartition < AbstractRest
    attr_reader :sys_uuid

    XMLMAP = {
      "PartitionName" => "name",
      "PartitionID" => "id",
      "PartitionState" => "state",
      "PartitionType" => "type",
      "PartitionMemoryConfiguration/CurrentMemory" => "memory",
      "PartitionProcessorConfiguration/HasDedicatedProcessors" => "dedicated",
      "ResourceMonitoringControlState" => "rmc_state",
      "ResourceMonitoringIPAddress" => "rmc_ipaddr"
    }.freeze

    def initialize(doc, type)
      super(doc)
      info = doc.elements["content/#{type}"]
      sys_href = info.elements["AssociatedManagedSystem"].attributes["href"]
      @sys_uuid = URI(sys_href).path.split('/').last
      get_values(info, XMLMAP)
    end
  end

  # Logical Partition information
  class LogicalPartition < BasePartition
    def initialize(doc)
      super(doc, "LogicalPartition:LogicalPartition")
    end
  end

  # VIOS information
  class VirtualIOServer < BasePartition
    def initialize(doc)
      super(doc, "VirtualIOServer:VirtualIOServer")
    end
  end

  # HMC Event
  class Event < AbstractRest
    XMLMAP = {
      "EventID" => "id",
      "EventType" => "type",
      "EventData" => "data",
      "EventDetail" => "detail",
    }.freeze

    def initialize(doc)
      super(doc)
      info = doc.elements["content/Event:Event"]
      get_values(info, XMLMAP)
    end
  end

  # Error response from HMC
  class HttpErrorResponse < AbstractRest
    XMLMAP = {
      "HTTPStatus" => "status",
      "RequestURI" => "uri",
      "ReasonCode" => "reason",
      "Message" => "message",
    }.freeze

    def initialize(doc)
      super(doc)
      info = doc.elements["content/HttpErrorResponse:HttpErrorResponse"]
      get_values(info, XMLMAP)
    end
  end
end
