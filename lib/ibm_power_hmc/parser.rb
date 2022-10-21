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

      type = content.attributes["type"].split("=")[1] || filter_type.to_s
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
      self.class.__send__(:define_method, "#{varname}=") do |v|
        if v.nil?
          xml.elements.delete(xpath)
        else
          create_element(xpath) if xml.elements[xpath].nil?
          xml.elements[xpath].text = v
        end
        instance_variable_set("@#{varname}", v)
      end
      instance_variable_set("@#{varname}", value)
    end
    private :define_attr

    ##
    # @!method create_element(xpath)
    # Create a new XML element.
    # @param xpath [String] The XPath of the XML element to create.
    def create_element(xpath)
      cur = xml
      xpath.split("/").each do |el|
        p = cur.elements[el]
        if p.nil?
          cur = cur.add_element(el)
        else
          cur = p
        end
      end
    end

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
      xml.get_elements([name, type].compact.join("/")).map do |elem|
        Module.const_get("IbmPowerHmc::#{elem.name}").new(elem)
      rescue NameError
        nil
      end.compact
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
      :maint_level => "VersionInfo/Maintenance",
      :sp_name => "VersionInfo/ServicePackName",
      :version => "BaseVersion",
      :ssh_pubkey => "PublicSSHKeyValue",
      :uvmid => "UVMID",
      :tz => "CurrentTimezone",
      :uptime => "ManagementConsoleUpTime",
      :uom_version => "UserObjectModelVersion/MinorVersion",
      :uom_schema => "UserObjectModelVersion/SchemaNamespace",
      :templates_version => "TemplateObjectModelVersion/MinorVersion",
      :templates_schema => "TemplateObjectModelVersion/SchemaNamespace",
      :web_version => "WebObjectModelVersion/MinorVersion",
      :web_schema => "WebObjectModelVersion/SchemaNamespace",
      :session_timeout => "SessionTimeout",
      :web_access => "RemoteWebAccess",
      :ssh_access => "RemoteCommandAccess",
      :vterm_access => "RemoteVirtualTerminalAccess"
    }.freeze

    def time
      Time.at(0, singleton("ManagementConsoleTime").to_i, :millisecond).utc
    end

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
      :ref_code => "ReferenceCode",
      :fwversion => "SystemFirmware",
      :memory => "AssociatedSystemMemoryConfiguration/InstalledSystemMemory",
      :avail_mem => "AssociatedSystemMemoryConfiguration/CurrentAvailableSystemMemory",
      :cpus => "AssociatedSystemProcessorConfiguration/InstalledSystemProcessorUnits",
      :avail_cpus => "AssociatedSystemProcessorConfiguration/CurrentAvailableSystemProcessorUnits",
      :mtype => "MachineTypeModelAndSerialNumber/MachineType",
      :model => "MachineTypeModelAndSerialNumber/Model",
      :serial => "MachineTypeModelAndSerialNumber/SerialNumber",
      :vtpm_version => "AssociatedSystemSecurity/VirtualTrustedPlatformModuleVersion",
      :vtpm_lpars => "AssociatedSystemSecurity/AvailableVirtualTrustedPlatformModulePartitions",
      :is_classic_hmc_mgmt => "IsClassicHMCManagement",
      :is_hmc_mgmt_master => "IsHMCPowerVMManagementMaster"
    }.freeze

    def group_uuids
      uuids_from_links("AssociatedGroups")
    end

    def time
      Time.at(0, singleton("SystemTime").to_i, :millisecond).utc
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

  class HostChannelAdapter < IOAdapter; end
  class PhysicalFibreChannelAdapter < IOAdapter; end
  class SRIOVAdapter < IOAdapter; end

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
      :cpu_compat_mode => "CurrentProcessorCompatibilityMode",
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

    def io_adapters
      collection_of("PartitionIOConfiguration/ProfileIOSlots/ProfileIOSlot/AssociatedIOSlot/RelatedIOAdapter", "*[1]")
    end

    def shared_processor_pool_uuid
      href = singleton("ProcessorPool", "href")
      uuid_from_href(href) unless href.nil?
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

    def seas
      collection_of("SharedEthernetAdapters", "SharedEthernetAdapter")
    end

    def trunks
      collection_of("TrunkAdapters", "TrunkAdapter")
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

  # SEA information
  class SharedEthernetAdapter < AbstractNonRest
    ATTRS = {
      :udid => "UniqueDeviceID",
      :name => "DeviceName",
      :state => "ConfigurationState",
      :large_send => "LargeSend",
      :vlan_id => "PortVLANID",
      :ha_mode => "HighAvailabilityMode",
      :qos_mode => "QualityOfServiceMode",
      :jumbo => "JumboFramesEnabled",
      :queue_size => "QueueSize",
      :primary => "IsPrimary"
    }.freeze

    def iface
      elem = xml.elements["IPInterface"]
      IPInterface.new(elem) unless elem.nil?
    end

    def device
      elem = xml.elements["BackingDeviceChoice/*[1]"]
      begin
        Module.const_get("IbmPowerHmc::#{elem.name}").new(elem) unless elem.nil?
      rescue NameError
        nil
      end
    end

    def trunks
      collection_of("TrunkAdapters", "TrunkAdapter")
    end
  end

  # IP Interface information
  class IPInterface < AbstractNonRest
    ATTRS = {
      :name     => "InterfaceName",
      :state    => "State",
      :hostname => "HostName",
      :ip       => "IPAddress",
      :netmask  => "SubnetMask",
      :gateway  => "Gateway",
      :prefix   => "IPV6Prefix",
    }.freeze
  end

  # Empty parent class to match K2 schema definition
  class VirtualSCSIStorage < AbstractNonRest; end

  # Physical Volume information
  class PhysicalVolume < VirtualSCSIStorage
    ATTRS = {
      :location => "LocationCode",
      :description => "Description",
      :is_available => "AvailableForUsage",
      :capacity => "VolumeCapacity", # in MiB
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
      :capacity => "DiskCapacity", # in GiB
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

  # SharedFileSystemFile information
  class SharedFileSystemFile < VirtualSCSIStorage
    ATTRS = {
      :name => "SharedFileSystemFileName",
      :path => "SharedFileSystemFilePath",
      :udid => "UniqueDeviceID"
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
      :required => "RequiredAdapter",
      :lpar_id  => "LocalPartitionID",
      :dr_name  => "DynamicReconfigurationConnectorName"
    }.freeze
  end

  # Virtual Ethernet Adapter information
  class VirtualEthernetAdapter < VirtualIOAdapter
    ATTRS = ATTRS.merge({
      :name       => "DeviceName",
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

  # Trunk Adapter information
  class TrunkAdapter < VirtualEthernetAdapter; end

  class EthernetBackingDevice < IOAdapter
    def iface
      elem = xml.elements["IPInterface"]
      IPInterface.new(elem) unless elem.nil?
    end
  end

  # LP-HEA information
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
      # LogicalUnit, PhysicalVolume, VirtualDisk, VirtualOpticalMedia,
      # SharedFileSystemFile
      elem = xml.elements["Storage/*[1]"]
      begin
        Module.const_get("IbmPowerHmc::#{elem.name}").new(elem) unless elem.nil?
      rescue NameError
        nil
      end
    end

    def device
      # Possible backing device types are:
      # LogicalVolumeVirtualTargetDevice, PhysicalVolumeVirtualTargetDevice,
      # SharedStoragePoolLogicalUnitVirtualTargetDevice, VirtualOpticalTargetDevice,
      # SharedFileSystemFileVirtualTargetDevice
      elem = xml.elements["TargetDevice/*[1]"]
      begin
        Module.const_get("IbmPowerHmc::#{elem.name}").new(elem) unless elem.nil?
      rescue NameError
        nil
      end
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

  # SharedFileSystemFile backing device information
  class SharedFileSystemFileVirtualTargetDevice < VirtualTargetDevice; end

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

  # Shared Processor Pool
  class SharedProcessorPool < AbstractRest
    ATTRS = {
      :name => "PoolName",
      :available => "AvailableProcUnits",
      :max => "MaximumProcessingUnits",
      :reserved => "CurrentReservedProcessingUnits",
      :pending_reserved => "PendingReservedProcessingUnits",
      :pool_id => "PoolID"
    }.freeze

    def lpar_uuids
      uuids_from_links("AssignedPartitions")
    end

    def sys_uuid
      uuid_from_href(href, -3)
    end
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
      :lpar_name    => "logicalPartitionConfig/partitionName",
      :lpar_type    => "logicalPartitionConfig/partitionType",
      :lpar_id      => "logicalPartitionConfig/partitionId",
      :os           => "logicalPartitionConfig/osVersion",
      :memory       => "logicalPartitionConfig/memoryConfiguration/currMemory",
      :dedicated    => "logicalPartitionConfig/processorConfiguration/hasDedicatedProcessors",
      :sharing_mode => "logicalPartitionConfig/processorConfiguration/sharingMode",
      :vprocs       => "logicalPartitionConfig/processorConfiguration/sharedProcessorConfiguration/desiredVirtualProcessors",
      :proc_units   => "logicalPartitionConfig/processorConfiguration/sharedProcessorConfiguration/desiredProcessingUnits",
      :procs        => "logicalPartitionConfig/processorConfiguration/dedicatedProcessorConfiguration/desiredProcessors"
    }.freeze

    def vscsi
      REXML::XPath.match(xml, 'logicalPartitionConfig/virtualSCSIClientAdapters/VirtualSCSIClientAdapter').map do |adap|
        {
          :vios     => adap.elements['connectingPartitionName']&.text,
          :physvol  => adap.elements['associatedPhysicalVolume/PhysicalVolume/name']&.text,
        }
      end
    end

    def vscsi=(list = [])
      adaps = REXML::Element.new('virtualSCSIClientAdapters')
      adaps.add_attribute('schemaVersion', 'V1_5_0')
      list.each do |vscsi|
        adaps.add_element('VirtualSCSIClientAdapter', {'schemaVersion' => 'V1_5_0'}).tap do |v|
          v.add_element('associatedLogicalUnits', {'schemaVersion' => 'V1_5_0'})
          v.add_element('associatedPhysicalVolume', {'schemaVersion' => 'V1_5_0'}).tap do |e|
            e.add_element('PhysicalVolume', {'schemaVersion' => 'V1_5_0'}).add_element('name').text = vscsi[:physvol] if vscsi[:physvol]
          end
          v.add_element('connectingPartitionName').text = vscsi[:vios]
          v.add_element('AssociatedTargetDevices', {'schemaVersion' => 'V1_5_0'})
          v.add_element('associatedVirtualOpticalMedia', {'schemaVersion' => 'V1_5_0'})
        end
      end
      if xml.elements['logicalPartitionConfig/virtualSCSIClientAdapters']
        xml.elements['logicalPartitionConfig/virtualSCSIClientAdapters'] = adaps
      else
        xml.elements['logicalPartitionConfig'].add_element(adaps)
      end
    end

    def vfc
      REXML::XPath.match(xml, 'logicalPartitionConfig/virtualFibreChannelClientAdapters/VirtualFibreChannelClientAdapter').map do |adap|
        {
          :vios => adap.elements['connectingPartitionName']&.text,
          :port => adap.elements['portName']&.text
        }
      end
    end

    def vfc=(list = [])
      adaps = REXML::Element.new('virtualFibreChannelClientAdapters')
      adaps.add_attribute('schemaVersion', 'V1_5_0')
      list.each do |vfc|
        adaps.add_element('VirtualFibreChannelClientAdapter', {'schemaVersion' => 'V1_5_0'}).tap do |v|
          v.add_element('connectingPartitionName').text = vfc[:vios]
          v.add_element('portName').text                = vfc[:port]
        end
      end
      if xml.elements['logicalPartitionConfig/virtualFibreChannelClientAdapters']
        xml.elements['logicalPartitionConfig/virtualFibreChannelClientAdapters'] = adaps
      else
        xml.elements['logicalPartitionConfig'].add_element(adaps)
      end
    end

    def vlans
      REXML::XPath.match(xml, 'logicalPartitionConfig/clientNetworkAdapters/ClientNetworkAdapter/clientVirtualNetworks/ClientVirtualNetwork').map do |vlan|
        {
          :name    => vlan.elements['name']&.text,
          :vlan_id => vlan.elements['vlanId']&.text,
          :switch  => vlan.elements['associatedSwitchName']&.text
        }
      end
    end

    def vlans=(list = [])
      adaps = REXML::Element.new('clientNetworkAdapters')
      adaps.add_attribute('schemaVersion', 'V1_5_0')
      list.each do |vlan|
        adaps.add_element('ClientNetworkAdapter',  {'schemaVersion' => 'V1_5_0'})
             .add_element('clientVirtualNetworks', {'schemaVersion' => 'V1_5_0'})
             .add_element('ClientVirtualNetwork',  {'schemaVersion' => 'V1_5_0'})
             .tap do |v|
          v.add_element('name').text                 = vlan[:name]
          v.add_element('vlanId').text               = vlan[:vlan_id]
          v.add_element('associatedSwitchName').text = vlan[:switch]
        end
      end
      xml.elements['logicalPartitionConfig/clientNetworkAdapters'] = adaps
    end
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
      :id        => "JobID",
      :status    => "Status",
      :operation => "JobRequestInstance/RequestedOperation/OperationName",
      :group     => "JobRequestInstance/RequestedOperation/GroupName",
      :message   => "ResponseException/Message"
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

  # Performance and Capacity Monitoring preferences
  class ManagementConsolePcmPreference < AbstractRest
    ATTRS = {
      :max_ltm                     => "MaximumManagedSystemsForLongTermMonitor",
      :max_compute_ltm             => "MaximumManagedSystemsForComputeLTM",
      :max_aggregation             => "MaximumManagedSystemsForAggregation",
      :max_stm                     => "MaximumManagedSystemsForShortTermMonitor",
      :max_em                      => "MaximumManagedSystemsForEnergyMonitor",
      :aggregated_storage_duration => "AggregatedMetricsStorageDuration"
    }.freeze

    def managed_system_preferences
      collection_of(nil, "ManagedSystemPcmPreference")
    end
  end

  class ManagedSystemPcmPreference < AbstractNonRest
    ATTRS = {
      :id                 => "Metadata/Atom/AtomID",
      :name               => "SystemName",
      :long_term_monitor  => "LongTermMonitorEnabled",
      :aggregation        => "AggregationEnabled",
      :short_term_monitor => "ShortTermMonitorEnabled",
      :compute_ltm        => "ComputeLTMEnabled",
      :energy_monitor     => "EnergyMonitorEnabled"
    }.freeze
  end

  # Serviceable Event
  class ServiceableEvent < AbstractRest
    ATTRS = {
      :prob_uuid => "problemUuid",
      :hostname => "reportingConsoleNode/hostName",
      :number => "problemNumber",
      :hw_record => "problemManagementHardwareRecord",
      :short_desc => "shortDescription",
      :state => "problemState",
      :approval_state => "ApprovalState",
      :refcode => "referenceCode",
      :refcode_ext => "referenceCodeExtension",
      :refcode_sys => "systemReferenceCode",
      :call_home => "callHomeEnabled",
      :dup_count => "duplicateCount",
      :severity => "eventSeverity",
      :notif_type => "notificationType",
      :notif_status => "notificationStatus",
      :post_action => "postAction",
      :symptom => "symptomString",
      :lpar_id => "partitionId",
      :lpar_name => "partitionName",
      :lpar_hostname => "partitionHostName",
      :lpar_ostype => "partitionOSType",
      :syslog_id => "sysLogId",
      :total_events => "totalEvents"
    }.freeze

    def reporting_mtms
      mtms("reportingManagedSystemNode")
    end

    def failing_mtms
      mtms("failingManagedSystemNode")
    end

    def time
      Time.at(0, singleton("primaryTimestamp").to_i, :millisecond).utc
    end

    def created_time
      Time.at(0, singleton("createdTimestamp").to_i, :millisecond).utc
    end

    def first_reported_time
      Time.at(0, singleton("firstReportedTimestamp").to_i, :millisecond).utc
    end

    def last_reported_time
      Time.at(0, singleton("lastReportedTimestamp").to_i, :millisecond).utc
    end

    def frus
      collection_of("fieldReplaceableUnits", "FieldReplaceableUnit")
    end

    def ext_files
      collection_of("extendedErrorData", "ExtendedFileData")
    end

    private

    def mtms(prefix)
      machtype = singleton("#{prefix}/managedTypeModelSerial/MachineType")
      model = singleton("#{prefix}/managedTypeModelSerial/Model")
      serial = singleton("#{prefix}/managedTypeModelSerial/SerialNumber")
      "#{machtype}-#{model}*#{serial}"
    end
  end

  class FieldReplaceableUnit < AbstractNonRest
    ATTRS = {
      :part_number => "partNumber",
      :fru_class => "class",
      :description => "fieldReplaceableUnitDescription",
      :location => "locationCode",
      :serial => "SerialNumber",
      :ccin => "ccin"
    }.freeze
  end

  class ExtendedFileData < AbstractNonRest
    ATTRS = {
      :filename    => "fileName",
      :description => "description",
      :zipfilename => "zipFileName"
    }.freeze
  end
end
