# frozen_string_literal: true

require 'time'
require 'uri'

module IbmPowerHmc
  ##
  # Generic parser for HMC K2 XML responses.
  class Parser
    def initialize(body)
      @doc = REXML::Document.new(body)
    end

    ##
    # @!method entry
    # Return the first K2 entry element in the response.
    # @return [REXML::Element, nil] The first entry element.
    def entry
      @doc.elements["entry"]
    end

    ##
    # @!method object(filter_type = nil)
    # Parse the first K2 entry element into an object.
    # @param filter_type [String] Entry type must match the specified type.
    # @return [IbmPowerHmc::AbstractRest, nil] The parsed object.
    def object(filter_type = nil)
      self.class.to_obj(entry, filter_type)
    end

    def self.to_obj(entry, filter_type = nil)
      return if entry.nil?

      content = entry.elements["content[@type]"]
      return if content.nil?

      type = content.attributes["type"].split("=").last
      return unless filter_type.nil? || filter_type.to_s == type

      Module.const_get("IbmPowerHmc::#{type}").new(entry)
    end
  end

  ##
  # Parser for HMC K2 feeds.
  # A feed encapsulates a list of entries like this:
  # <feed>
  #   <entry>
  #     <!-- entry #1 -->
  #   </entry>
  #   <entry>
  #     <!-- entry #2 -->
  #   </entry>
  #   ...
  # </feed>
  class FeedParser < Parser
    def entries
      objs = []
      @doc.each_element("feed/entry") do |entry|
        objs << yield(entry)
      end
      objs
    end

    ##
    # @!method objects(filter_type = nil)
    # Parse feed entries into objects.
    # @param filter_type [String] Filter entries based on content type.
    # @return [Array<IbmPowerHmc::AbstractRest>] The list of objects.
    def objects(filter_type = nil)
      entries do |entry|
        self.class.to_obj(entry, filter_type)
      end.compact
    end
  end

  ##
  # HMC generic K2 non-REST object.
  # @abstract
  # @attr_reader [REXML::Document] xml The XML document representing this object.
  class AbstractNonRest
    ATTRS = {}.freeze
    attr_reader :xml

    def initialize(xml)
      @xml = xml
      self.class::ATTRS.each { |varname, xpath| define_attr(varname, xpath) }
    end

    ##
    # @!method define_attr(varname, xpath)
    # Define an instance variable using the text of an XML element as value.
    # @param varname [String] The name of the instance variable.
    # @param xpath [String] The XPath of the XML element containing the text.
    def define_attr(varname, xpath)
      value = singleton(xpath)
      self.class.__send__(:attr_reader, varname)
      instance_variable_set("@#{varname}", value)
    end
    private :define_attr

    ##
    # @!method singleton(xpath, attr = nil)
    # Get the text (or the value of a specified attribute) of an XML element.
    # @param xpath [String] The XPath of the XML element.
    # @param attr [String] The name of the attribute.
    # @return [String, nil] The text or attribute value of the XML element or nil.
    # @example lpar.singleton("PartitionProcessorConfiguration/*/MaximumVirtualProcessors").to_i
    def singleton(xpath, attr = nil)
      elem = xml.elements[xpath]
      return if elem.nil?

      attr.nil? ? elem.text&.strip : elem.attributes[attr]
    end

    def to_s
      str = +"#{self.class.name}:\n"
      self.class::ATTRS.each do |varname, _|
        value = instance_variable_get("@#{varname}")
        value = value.nil? ? "null" : "'#{value}'"
        str << "  #{varname}: #{value}\n"
      end
      str
    end

    def uuid_from_href(href, index = -1)
      URI(href).path.split('/')[index]
    end

    def uuids_from_links(elem, index = -1)
      xml.get_elements("#{elem}/link[@href]").map do |link|
        uuid_from_href(link.attributes["href"], index)
      end.compact
    end

    def collection_of(name, type)
      objtype = Module.const_get("IbmPowerHmc::#{type}")
      xml.get_elements("#{name}/#{type}").map do |elem|
        objtype.new(elem)
      end
    rescue
      []
    end
  end

  ##
  # HMC generic K2 REST object.
  # Encapsulate data for a single REST object.
  # The XML looks like this:
  # <entry>
  #   <id>uuid</id>
  #   <published>timestamp</published>
  #   <link rel="SELF" href="https://..."/>
  #   <etag:etag>ETag</etag:etag>
  #   <content type="type">
  #     <!-- actual content here -->
  #   </content>
  # </entry>
  #
  # @abstract
  # @attr_reader [String] uuid The UUID of the object contained in the entry.
  # @attr_reader [Time] published The time at which the entry was published.
  # @attr_reader [URI::HTTPS] href The URL of the object itself.
  # @attr_reader [String] etag The entity tag of the entry.
  # @attr_reader [String] content_type The content type of the object contained in the entry.
  class AbstractRest < AbstractNonRest
    attr_reader :uuid, :published, :href, :etag, :content_type

    def initialize(entry)
      if entry.name != "entry"
        # We are inlined.
        super(entry)
        return
      end

      @uuid = entry.elements["id"]&.text
      @published = Time.xmlschema(entry.elements["published"]&.text)
      link = entry.elements["link[@rel='SELF']"]
      @href = URI(link.attributes["href"]) unless link.nil?
      @etag = entry.elements["etag:etag"]&.text&.strip
      content = entry.elements["content"]
      @content_type = content.attributes["type"]
      super(content.elements.first)
    end

    def to_s
      str = super
      str << "  uuid: '#{uuid}'\n" if defined?(@uuid)
      str << "  published: '#{published}'\n" if defined?(@published)
      str
    end
  end

  # HMC information
  class ManagementConsole < AbstractRest
    ATTRS = {
      :name => "ManagementConsoleName",
      :build_level => "VersionInfo/BuildLevel",
      :version => "BaseVersion",
      :ssh_pubkey => "PublicSSHKeyValue"
    }.freeze

    def managed_systems_uuids
      uuids_from_links("ManagedSystems")
    end

    def ssh_authkeys
      xml.get_elements("AuthorizedKeysValue/AuthorizedKey").map do |elem|
        elem.text&.strip
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
      :description => "Description",
      :location => "SystemLocation", # Rack/Unit
      :fwversion => "SystemFirmware",
      :memory => "AssociatedSystemMemoryConfiguration/InstalledSystemMemory",
      :avail_mem => "AssociatedSystemMemoryConfiguration/CurrentAvailableSystemMemory",
      :cpus => "AssociatedSystemProcessorConfiguration/InstalledSystemProcessorUnits",
      :avail_cpus => "AssociatedSystemProcessorConfiguration/CurrentAvailableSystemProcessorUnits",
      :mtype => "MachineTypeModelAndSerialNumber/MachineType",
      :model => "MachineTypeModelAndSerialNumber/Model",
      :serial => "MachineTypeModelAndSerialNumber/SerialNumber",
      :vtpm_version => "AssociatedSystemSecurity/VirtualTrustedPlatformModuleVersion",
      :vtpm_lpars => "AssociatedSystemSecurity/AvailableVirtualTrustedPlatformModulePartitions"
    }.freeze

    def group_uuids
      uuids_from_links("AssociatedGroups")
    end

    def time
      Time.at(0, singleton("SystemTime").to_i, :millisecond)
    end

    def capabilities
      xml.get_elements("AssociatedSystemCapabilities/*").map do |elem|
        elem.name unless elem.text&.strip != "true"
      end.compact
    end

    def cpu_compat_modes
      xml.get_elements("AssociatedSystemProcessorConfiguration/SupportedPartitionProcessorCompatibilityModes").map do |elem|
        elem.text&.strip
      end.compact
    end

    def lpars_uuids
      uuids_from_links("AssociatedLogicalPartitions")
    end

    def vioses_uuids
      uuids_from_links("AssociatedVirtualIOServers")
    end

    def io_adapters
      collection_of("AssociatedSystemIOConfiguration/IOSlots/IOSlot/RelatedIOAdapter", "IOAdapter")
    end

    def vswitches_uuids
      uuids_from_links("AssociatedSystemIOConfiguration/AssociatedSystemVirtualNetwork/VirtualSwitches")
    end

    def networks_uuids
      uuids_from_links("AssociatedSystemIOConfiguration/AssociatedSystemVirtualNetwork/VirtualNetworks")
    end
  end

  # I/O Adapter information
  class IOAdapter < AbstractNonRest
    ATTRS = {
      :id => "AdapterID",
      :description => "Description",
      :name => "DeviceName",
      :type => "DeviceType",
      :dr_name => "DynamicReconfigurationConnectorName",
      :udid => "UniqueDeviceID"
    }.freeze
  end

  # Common class for LPAR and VIOS
  class BasePartition < AbstractRest
    ATTRS = {
      :name => "PartitionName",
      :id => "PartitionID",
      :state => "PartitionState",
      :type => "PartitionType",
      :memory => "PartitionMemoryConfiguration/CurrentMemory",
      :dedicated => "PartitionProcessorConfiguration/CurrentHasDedicatedProcessors",
      :sharing_mode => "PartitionProcessorConfiguration/CurrentSharingMode",
      :rmc_state => "ResourceMonitoringControlState",
      :rmc_ipaddr => "ResourceMonitoringIPAddress",
      :os => "OperatingSystemVersion",
      :ref_code => "ReferenceCode",
      :procs => "PartitionProcessorConfiguration/CurrentDedicatedProcessorConfiguration/CurrentProcessors",
      :proc_units => "PartitionProcessorConfiguration/CurrentSharedProcessorConfiguration/CurrentProcessingUnits",
      :vprocs => "PartitionProcessorConfiguration/CurrentSharedProcessorConfiguration/AllocatedVirtualProcessors",
      :description => "Description"
    }.freeze

    def sys_uuid
      href = singleton("AssociatedManagedSystem", "href")
      uuid_from_href(href) unless href.nil?
    end

    def group_uuids
      uuids_from_links("AssociatedGroups")
    end

    def net_adap_uuids
      uuids_from_links("ClientNetworkAdapters")
    end

    def lhea_ports
      collection_of("HostEthernetAdapterLogicalPorts", "HostEthernetAdapterLogicalPort")
    end

    def sriov_elp_uuids
      uuids_from_links("SRIOVEthernetLogicalPorts")
    end

    # Setters

    def name=(name)
      xml.elements[ATTRS[:name]].text = name
      @name = name
    end
  end

  # Logical Partition information
  class LogicalPartition < BasePartition
    def vnic_dedicated_uuids
      uuids_from_links("DedicatedVirtualNICs")
    end

    def vscsi_client_uuids
      uuids_from_links("VirtualSCSIClientAdapters")
    end

    def vfc_client_uuids
      uuids_from_links("VirtualFibreChannelClientAdapters")
    end
  end

  # VIOS information
  class VirtualIOServer < BasePartition
    def pvs
      collection_of("PhysicalVolumes", "PhysicalVolume")
    end

    def rep
      elem = xml.elements["MediaRepositories/VirtualMediaRepository"]
      VirtualMediaRepository.new(elem) unless elem.nil?
    end

    def vscsi_mappings
      collection_of("VirtualSCSIMappings", "VirtualSCSIMapping")
    end

    def vfc_mappings
      collection_of("VirtualFibreChannelMappings", "VirtualFibreChannelMapping")
    end
  end

  # Group information
  class Group < AbstractRest
    ATTRS = {
      :name => "GroupName",
      :description => "GroupDescription",
      :color => "GroupColor"
    }.freeze

    def sys_uuids
      uuids_from_links("AssociatedManagedSystems")
    end

    def lpar_uuids
      uuids_from_links("AssociatedLogicalPartitions")
    end

    def vios_uuids
      uuids_from_links("AssociatedVirtualIOServers")
    end
  end

  # Empty parent class to match K2 schema definition
  class VirtualSCSIStorage < AbstractNonRest; end

  # Physical Volume information
  class PhysicalVolume < VirtualSCSIStorage
    ATTRS = {
      :location => "LocationCode",
      :description => "Description",
      :is_available => "AvailableForUsage",
      :capacity => "VolumeCapacity",
      :name => "VolumeName",
      :is_fc => "IsFibreChannelBacked",
      :udid => "VolumeUniqueID"
    }.freeze
  end

  # Logical Volume information
  class VirtualDisk < VirtualSCSIStorage
    ATTRS = {
      :name => "DiskName",
      :label => "DiskLabel",
      :capacity => "DiskCapacity", # In GiB
      :psize => "PartitionSize",
      :vg => "VolumeGroup",
      :udid => "UniqueDeviceID"
    }.freeze
  end

  # Virtual CD-ROM information
  class VirtualOpticalMedia < VirtualSCSIStorage
    ATTRS = {
      :name => "MediaName",
      :udid => "MediaUDID",
      :mount_opts => "MountType",
      :size => "Size" # in GiB
    }.freeze
  end

  # Virtual Media Repository information
  class VirtualMediaRepository < AbstractNonRest
    ATTRS = {
      :name => "RepositoryName",
      :size => "RepositorySize" # in GiB
    }.freeze

    def vopts
      collection_of("OpticalMedia", "VirtualOpticalMedia")
    end
  end

  # Virtual Switch information
  class VirtualSwitch < AbstractRest
    ATTRS = {
      :id   => "SwitchID",
      :mode => "SwitchMode", # "VEB", "VEPA"
      :name => "SwitchName"
    }.freeze

    def sys_uuid
      href.path.split('/')[-3]
    end

    def networks_uuids
      uuids_from_links("VirtualNetworks")
    end
  end

  # Virtual Network information
  class VirtualNetwork < AbstractRest
    ATTRS = {
      :name       => "NetworkName",
      :vlan_id    => "NetworkVLANID",
      :vswitch_id => "VswitchID",
      :tagged     => "TaggedNetwork"
    }.freeze

    def vswitch_uuid
      href = singleton("AssociatedSwitch", "href")
      uuid_from_href(href) unless href.nil?
    end

    def lpars_uuids
      uuids_from_links("ConnectedPartitions")
    end
  end

  # Virtual I/O Adapter information
  class VirtualIOAdapter < AbstractRest
    ATTRS = {
      :type     => "AdapterType", # "Server", "Client", "Unknown"
      :location => "LocationCode",
      :slot     => "VirtualSlotNumber",
      :required => "RequiredAdapter"
    }.freeze
  end

  # Virtual Ethernet Adapter information
  class VirtualEthernetAdapter < VirtualIOAdapter
    ATTRS = ATTRS.merge({
      :macaddr    => "MACAddress",
      :vswitch_id => "VirtualSwitchID",
      :vlan_id    => "PortVLANID",
      :location   => "LocationCode"
    }.freeze)

    def vswitch_uuid
      uuids_from_links("AssociatedVirtualSwitch").first
    end
  end

  # Client Network Adapter information
  class ClientNetworkAdapter < VirtualEthernetAdapter
    def networks_uuids
      uuids_from_links("VirtualNetworks")
    end
  end

  # LP-HEA information
  class EthernetBackingDevice < IOAdapter; end
  class HostEthernetAdapterLogicalPort < EthernetBackingDevice
    ATTRS = ATTRS.merge({
      :macaddr  => "MACAddress",
      :port_id  => "LogicalPortID",
      :state    => "PortState",
      :location => "HEALogicalPortPhysicalLocation"
    }.freeze)
  end

  # Virtual NIC dedicated information
  class VirtualNICDedicated < VirtualIOAdapter
    ATTRS = ATTRS.merge({
      :location     => "DynamicReconfigurationConnectorName", # overrides VirtualIOAdapter
      :macaddr      => "Details/MACAddress",
      :os_devname   => "Details/OSDeviceName",
      :port_vlan_id => "Details/PortVLANID"
    }.freeze)
  end

  # SR-IOV Configured Logical Port information
  class SRIOVConfiguredLogicalPort < AbstractRest
    ATTRS = {
      :port_id      => "LogicalPortID",
      :port_vlan_id => "PortVLANID",
      :location     => "LocationCode",
      :dr_name      => "DynamicReconfigurationConnectorName",
      :devname      => "DeviceName",
      :capacity     => "ConfiguredCapacity"
    }.freeze

    def lpars_uuids
      uuids_from_links("AssociatedLogicalPartitions")
    end
  end

  # SR-IOV Ethernet Logical Port information
  class SRIOVEthernetLogicalPort < SRIOVConfiguredLogicalPort
    ATTRS = ATTRS.merge({
      :macaddr => "MACAddress"
    }.freeze)
  end

  # Virtual SCSI mapping information
  class VirtualSCSIMapping < AbstractNonRest
    def lpar_uuid
      href = singleton("AssociatedLogicalPartition", "href")
      uuid_from_href(href) unless href.nil?
    end

    def client
      elem = xml.elements["ClientAdapter"]
      VirtualSCSIClientAdapter.new(elem) unless elem.nil?
    end

    def server
      elem = xml.elements["ServerAdapter"]
      VirtualSCSIServerAdapter.new(elem) unless elem.nil?
    end

    def storage
      # Possible storage types are:
      # LogicalUnit, PhysicalVolume, VirtualDisk, VirtualOpticalMedia
      elem = xml.elements["Storage/*[1]"]
      Module.const_get("IbmPowerHmc::#{elem.name}").new(elem) unless elem.nil?
    end

    def device
      # Possible backing device types are:
      # LogicalVolumeVirtualTargetDevice, PhysicalVolumeVirtualTargetDevice,
      # SharedStoragePoolLogicalUnitVirtualTargetDevice, VirtualOpticalTargetDevice
      elem = xml.elements["TargetDevice/*[1]"]
      Module.const_get("IbmPowerHmc::#{elem.name}").new(elem) unless elem.nil?
    end
  end

  # Virtual SCSI adapter (common class for Client and Server)
  class VirtualSCSIAdapter < VirtualIOAdapter
    ATTRS = ATTRS.merge({
      :name => "AdapterName",
      :backdev => "BackingDeviceName",
      :remote_backdev => "RemoteBackingDeviceName",
      :remote_lpar_id => "RemoteLogicalPartitionID",
      :remote_slot => "RemoteSlotNumber",
      :server_location => "ServerLocationCode",
      :udid => "UniqueDeviceID"
    }.freeze)
  end

  # Virtual SCSI client adapter information
  class VirtualSCSIClientAdapter < VirtualSCSIAdapter
    def server
      elem = xml.elements["ServerAdapter"]
      VirtualSCSIServerAdapter.new(elem) unless elem.nil?
    end

    def vios_uuid
      href = singleton("ConnectingPartition", "href")
      uuid_from_href(href) unless href.nil?
    end
  end

  # Virtual SCSI server adapter information
  class VirtualSCSIServerAdapter < VirtualSCSIAdapter; end

  # Virtual target device information
  class VirtualTargetDevice < AbstractNonRest
    ATTRS = {
      :lun => "LogicalUnitAddress",
      :parent => "ParentName",
      :target => "TargetName",
      :udid => "UniqueDeviceID"
    }.freeze
  end

  # LV backing device information
  class LogicalVolumeVirtualTargetDevice < VirtualTargetDevice; end

  # PV backing device information
  class PhysicalVolumeVirtualTargetDevice < VirtualTargetDevice; end

  # LU backing device information
  class SharedStoragePoolLogicalUnitVirtualTargetDevice < VirtualTargetDevice
    ATTRS = ATTRS.merge({
      :cluster_id => "ClusterID",
      :path => "PathName",
      :raid_level => "RAIDLevel"
    }.freeze)
  end

  # Virtual CD backing device information
  class VirtualOpticalTargetDevice < VirtualTargetDevice
    def media
      elem = xml.elements["VirtualOpticalMedia"]
      VirtualOpticalMedia.new(elem) unless elem.nil?
    end
  end

  # VFC mapping information
  class VirtualFibreChannelMapping < AbstractNonRest
    def lpar_uuid
      href = singleton("AssociatedLogicalPartition", "href")
      uuid_from_href(href) unless href.nil?
    end

    def client
      elem = xml.elements["ClientAdapter"]
      VirtualFibreChannelClientAdapter.new(elem) unless elem.nil?
    end

    def server
      elem = xml.elements["ServerAdapter"]
      VirtualFibreChannelServerAdapter.new(elem) unless elem.nil?
    end

    def port
      elem = xml.elements["Port"]
      PhysicalFibreChannelPort.new(elem) unless elem.nil?
    end
  end

  # VFC adapter information
  class VirtualFibreChannelAdapter < VirtualIOAdapter
    ATTRS = ATTRS.merge({
      :name => "AdapterName",
      :lpar_id => "ConnectingPartitionID",
      :slot => "ConnectingVirtualSlotNumber",
      :udid => "UniqueDeviceID"
    }.freeze)

    def lpar_uuid
      href = singleton("ConnectingPartition", "href")
      uuid_from_href(href) unless href.nil?
    end
  end

  # VFC client information
  class VirtualFibreChannelClientAdapter < VirtualFibreChannelAdapter
    def nport_loggedin
      collection_of("NportLoggedInStatus", "VirtualFibreChannelNPortLoginStatus")
    end

    def server
      elem = xml.elements["ServerAdapter"]
      VirtualFibreChannelServerAdapter.new(elem) unless elem.nil?
    end

    def wwpns
      singleton("WWPNs")&.split
    end

    def os_disks
      xml.get_elements("OperatingSystemDisks/OperatingSystemDisk/Name").map do |elem|
        elem.text&.strip
      end.compact
    end
  end

  # VFC port status
  class VirtualFibreChannelNPortLoginStatus < AbstractNonRest
    ATTRS = {
      :wwpn => "WWPN",
      :wwpn_status => "WWPNStatus",
      :loggedin_by => "LoggedInBy",
      :reason => "StatusReason"
    }.freeze
  end

  # VFC server information
  class VirtualFibreChannelServerAdapter < VirtualFibreChannelAdapter
    ATTRS = ATTRS.merge({
      :map_port => "MapPort"
    }.freeze)

    def port
      elem = xml.elements["PhysicalPort"]
      PhysicalFibreChannelPort.new(elem) unless elem.nil?
    end
  end

  # FC port information
  class PhysicalFibreChannelPort < AbstractNonRest
    ATTRS = {
      :location => "LocationCode",
      :name => "PortName",
      :udid => "UniqueDeviceID",
      :wwpn => "WWPN",
      :wwnn => "WWNN",
      :avail_ports => "AvailablePorts",
      :total_ports => "TotalPorts"
    }.freeze

    def pvs
      collection_of("PhysicalVolumes", "PhysicalVolume")
    end
  end

  # Cluster information
  class Cluster < AbstractRest
    ATTRS = {
      :name => "ClusterName",
      :id => "ClusterID",
      :tier_capable => "ClusterCapabilities/IsTierCapable"
    }.freeze

    def repopvs
      collection_of("RepositoryDisk", "PhysicalVolume")
    end

    def ssp_uuid
      href = singleton("ClusterSharedStoragePool", "href")
      uuid_from_href(href) unless href.nil?
    end

    def nodes
      collection_of("Node", "Node")
    end
  end

  # Cluster node information
  class Node < AbstractNonRest
    ATTRS = {
      :hostname => "HostName",
      :lpar_id => "PartitionID",
      :state => "State",
      :ioslevel => "VirtualIOServerLevel"
    }.freeze

    def vios_uuid
      href = singleton("VirtualIOServer", "href")
      uuid_from_href(href) unless href.nil?
    end
  end

  # SSP information
  class SharedStoragePool < AbstractRest
    ATTRS = {
      :id => "SharedStoragePoolID",
      :name => "StoragePoolName",
      :udid => "UniqueDeviceID",
      :capacity => "Capacity",
      :free_space => "FreeSpace",
      :overcommit => "OverCommitSpace",
      :total_lu_size => "TotalLogicalUnitSize",
      :alert_threshold => "AlertThreshold"
    }.freeze

    def cluster_uuid
      href = singleton("AssociatedCluster", "href")
      uuid_from_href(href) unless href.nil?
    end

    def pvs
      collection_of("PhysicalVolumes", "PhysicalVolume")
    end

    def tiers_uuids
      uuids_from_links("AssociatedTiers")
    end

    def lus
      collection_of("LogicalUnits", "LogicalUnit")
    end
  end

  # SSP tier information
  class Tier < AbstractRest
    ATTRS = {
      :name => "Name",
      :udid => "UniqueDeviceID",
      :type => "Type",
      :capacity => "Capacity",
      :total_lu_size => "TotalLogicalUnitSize",
      :is_default => "IsDefault",
      :free_space => "FreeSpace"
    }.freeze

    def ssp_uuid
      href = singleton("AssociatedSharedStoragePool", "href")
      uuid_from_href(href) unless href.nil?
    end

    def lus_uuids
      uuids_from_links("AssociatedLogicalUnits")
    end
  end

  # SSP LU information
  class LogicalUnit < VirtualSCSIStorage
    ATTRS = {
      :name => "UnitName",
      :capacity => "UnitCapacity",
      :udid => "UniqueDeviceID",
      :thin => "ThinDevice",
      :type => "LogicalUnitType",
      :in_use => "InUse"
    }.freeze
  end

  class PartitionTemplateSummary < AbstractRest
    ATTRS = {
      :name => "partitionTemplateName"
    }.freeze
  end

  class PartitionTemplate < AbstractRest
    ATTRS = {
      :name         => "partitionTemplateName",
      :description  => "description",
      :os           => "logicalPartitionConfig/osVersion",
      :memory       => "logicalPartitionConfig/memoryConfiguration/currMemory",
      :dedicated    => "logicalPartitionConfig/processorConfiguration/hasDedicatedProcessors",
      :sharing_mode => "logicalPartitionConfig/processorConfiguration/sharingMode",
      :vprocs       => "logicalPartitionConfig/processorConfiguration/sharedProcessorConfiguration/desiredVirtualProcessors",
      :proc_units   => "logicalPartitionConfig/processorConfiguration/sharedProcessorConfiguration/desiredProcessingUnits",
      :procs        => "logicalPartitionConfig/processorConfiguration/dedicatedProcessorConfiguration/desiredProcessors"
    }.freeze
  end

  # HMC Event
  class Event < AbstractRest
    attr_accessor :usertask
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
      xml.each_element("Results/JobParameter") do |jobparam|
        name = jobparam.elements["ParameterName"]&.text&.strip
        value = jobparam.elements["ParameterValue"]&.text&.strip
        results[name] = value unless name.nil?
      end
      results
    end
  end
end
