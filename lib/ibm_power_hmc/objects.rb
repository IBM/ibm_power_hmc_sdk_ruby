# frozen_string_literal: true

require 'uri'

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  # HMC generic object
  class HmcObject
    attr_reader :uuid, :xml

    def initialize(doc)
      @uuid = doc.elements["id"].text
      @xml = doc
    end

    def get_value(doc, xpath, varname)
      value = doc.elements[xpath]
      value = value.text unless value.nil?
      value = value.strip unless value.nil?
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
  class ManagementConsole < HmcObject
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
  class ManagedSystem < HmcObject
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

  # Logical Partition information
  class LogicalPartition < HmcObject
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

    def initialize(doc)
      super(doc)
      info = doc.elements["content/LogicalPartition:LogicalPartition"]
      sys_href = info.elements["AssociatedManagedSystem"].attributes["href"]
      @sys_uuid = URI(sys_href).path.split('/').last
      get_values(info, XMLMAP)
    end
  end

  # VIOS information
  class VirtualIOServer < HmcObject
    attr_reader :sys_uuid

    XMLMAP = {
      "PartitionName" => "name",
      "PartitionID" => "id",
      "PartitionState" => "state",
      "PartitionType" => "type",
      "PartitionMemoryConfiguration/CurrentMemory" => "memory",
      "PartitionProcessorConfiguration/HasDedicatedProcessors" => "dedicated"
    }.freeze

    def initialize(doc)
      super(doc)
      info = doc.elements["content/VirtualIOServer:VirtualIOServer"]
      sys_href = info.elements["AssociatedManagedSystem"].attributes["href"]
      @sys_uuid = URI(sys_href).path.split('/').last
      get_values(info, XMLMAP)
    end
  end

  # HMC Event
  class Event < HmcObject
    attr_reader :published

    XMLMAP = {
      "EventID" => "id",
      "EventType" => "type",
      "EventData" => "data",
      "EventDetail" => "detail",
    }.freeze

    def initialize(doc)
      super(doc)
      @published = doc.elements["published"].text
      info = doc.elements["content/Event:Event"]
      get_values(info, XMLMAP)
    end
  end

  # Error response from HMC
  class HttpErrorResponse < HmcObject
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
