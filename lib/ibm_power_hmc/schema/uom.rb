# frozen_string_literal: true

require 'base64'

module IbmPowerHmc
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
      timestamp("ManagementConsoleTime")
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
      timestamp("SystemTime")
    end

    def capabilities
      xml.get_elements("AssociatedSystemCapabilities/*").map do |elem|
        elem.name if elem.text&.strip == "true"
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

    # Deprecated: use io_slots.io_adapter
    def io_adapters
      collection_of("AssociatedSystemIOConfiguration/IOSlots/IOSlot/RelatedIOAdapter", "IOAdapter")
    end

    def io_slots
      collection_of("AssociatedSystemIOConfiguration/IOSlots", "IOSlot")
    end

    def vswitches_uuids
      uuids_from_links("AssociatedSystemIOConfiguration/AssociatedSystemVirtualNetwork/VirtualSwitches")
    end

    def networks_uuids
      uuids_from_links("AssociatedSystemIOConfiguration/AssociatedSystemVirtualNetwork/VirtualNetworks")
    end
  end

  # I/O Slot information
  class IOSlot < AbstractNonRest
    ATTRS = {
      :description => "Description",
      :lpar_id => "PartitionID",
      :lpar_name => "PartitionName",
      :lpar_type => "PartitionType",
      :pci_class => "PCIClass",
      :pci_dev => "PCIDeviceID",
      :pci_subsys_dev => "PCISubsystemDeviceID",
      :pci_man => "PCIManufacturerID",
      :pci_rev => "PCIRevisionID",
      :pci_vendor => "PCIVendorID",
      :pci_subsys_vendor => "PCISubsystemVendorID",
      :dr_name => "SlotDynamicReconfigurationConnectorName",
      :physloc => "SlotPhysicalLocationCode",
      :sriov_capable_dev => "SRIOVCapableDevice",
      :sriov_capable => "SRIOVCapableSlot",
      :vpd_model => "VitalProductDataModel",
      :vpd_serial => "VitalProductDataSerialNumber",
      :vpd_stale => "VitalProductDataStale",
      :vpd_type => "VitalProductDataType"
    }.freeze

    def io_adapter
      elem = xml.elements["RelatedIOAdapter/*[1]"]
      Module.const_get("IbmPowerHmc::#{elem.name}").new(elem) unless elem.nil?
    rescue NameError
      nil
    end

    def features
      xml.get_elements("FeatureCodes").map do |elem|
        elem.text&.strip
      end.compact
    end

    def ior_devices
      collection_of("IORDevices", "IORDevice")
    end
  end

  # I/O Device information
  class IORDevice < AbstractNonRest
    ATTRS = {
      :parent => "ParentName",
      :pci_dev => "PCIDeviceId",
      :pci_vendor => "PCIVendorId",
      :pci_subsys_dev => "PCISubsystemDeviceId",
      :pci_subsys_vendor => "PCISubsystemVendorId",
      :pci_rev => "PCIRevisionId",
      :pci_class => "PCIClassCode",
      :type => "DeviceType",
      :serial => "SerialNumber",
      :fru_number => "FruNumber",
      :part_number => "PartNumber",
      :ccin => "CCIN",
      :size => "Size",
      :location => "LocationCode",
      :ucode_version => "MicroCodeVersion",
      :wwpn => "WWPN",
      :wwnn => "WWNN",
      :macaddr => "MacAddressValue",
      :description => "Description"
    }.freeze
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
  class SRIOVAdapter < IOAdapter; end

  # FC adapter information
  class PhysicalFibreChannelAdapter < IOAdapter
    def ports
      collection_of("PhysicalFibreChannelPorts", "PhysicalFibreChannelPort")
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
      :total_ports => "TotalPorts",
      :label => "Label"
    }.freeze

    def pvs
      collection_of("PhysicalVolumes", "PhysicalVolume")
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
      :desired_memory => "PartitionMemoryConfiguration/DesiredMemory",
      :min_memory => "PartitionMemoryConfiguration/MinimumMemory",
      :max_memory => "PartitionMemoryConfiguration/MaximumMemory",
      :ams => "PartitionMemoryConfiguration/ActiveMemorySharingEnabled",
      :shared_mem => "PartitionMemoryConfiguration/SharedMemoryEnabled",
      :dedicated => "PartitionProcessorConfiguration/CurrentHasDedicatedProcessors",
      :sharing_mode => "PartitionProcessorConfiguration/CurrentSharingMode",
      :uncapped_weight => "PartitionProcessorConfiguration/CurrentSharedProcessorConfiguration/CurrentUncappedWeight",
      :desired_uncapped_weight => "PartitionProcessorConfiguration/SharedProcessorConfiguration/UncappedWeight",
      :rmc_state => "ResourceMonitoringControlState",
      :rmc_ipaddr => "ResourceMonitoringIPAddress",
      :os => "OperatingSystemVersion",
      :ref_code => "ReferenceCode",
      :procs => "PartitionProcessorConfiguration/CurrentDedicatedProcessorConfiguration/CurrentProcessors",
      :desired_procs => "PartitionProcessorConfiguration/DedicatedProcessorConfiguration/DesiredProcessors",
      :minimum_procs => "PartitionProcessorConfiguration/DedicatedProcessorConfiguration/MinimumProcessors",
      :maximum_procs => "PartitionProcessorConfiguration/DedicatedProcessorConfiguration/MaximumProcessors",
      :proc_units => "PartitionProcessorConfiguration/CurrentSharedProcessorConfiguration/CurrentProcessingUnits",
      :vprocs => "PartitionProcessorConfiguration/CurrentSharedProcessorConfiguration/AllocatedVirtualProcessors",
      :desired_proc_units => "PartitionProcessorConfiguration/SharedProcessorConfiguration/DesiredProcessingUnits",
      :desired_vprocs => "PartitionProcessorConfiguration/SharedProcessorConfiguration/DesiredVirtualProcessors",
      :minimum_proc_units => "PartitionProcessorConfiguration/SharedProcessorConfiguration/MinimumProcessingUnits",
      :minimum_vprocs => "PartitionProcessorConfiguration/SharedProcessorConfiguration/MinimumVirtualProcessors",
      :maximum_proc_units => "PartitionProcessorConfiguration/SharedProcessorConfiguration/MaximumProcessingUnits",
      :maximum_vprocs => "PartitionProcessorConfiguration/SharedProcessorConfiguration/MaximumVirtualProcessors",
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

    def capabilities
      xml.get_elements("PartitionCapabilities/*").map do |elem|
        elem.name if elem.text&.strip == "true"
      end.compact
    end

    # Deprecated: use io_slots.io_adapter
    def io_adapters
      collection_of("PartitionIOConfiguration/ProfileIOSlots/ProfileIOSlot/AssociatedIOSlot/RelatedIOAdapter", "*[1]")
    end

    def io_slots
      xml.get_elements("PartitionIOConfiguration/ProfileIOSlots/ProfileIOSlot/AssociatedIOSlot").map do |elem|
        IOSlot.new(elem)
      end.compact
    end

    def shared_processor_pool_uuid
      href = singleton("ProcessorPool", "href")
      uuid_from_href(href) unless href.nil?
    end

    def paging_vios_uuid
      href = singleton("PartitionMemoryConfiguration/CurrentPagingServicePartition", "href")
      uuid_from_href(href) unless href.nil?
    end

    def paging_vios_uuids
      ["PrimaryPagingServicePartition", "SecondaryPagingServicePartition"].map do |name|
        href = singleton("PartitionMemoryConfiguration/#{name}", "href")
        uuid_from_href(href) unless href.nil?
      end
    end
  end

  # Logical Partition information
  class LogicalPartition < BasePartition
    ATTRS = ATTRS.merge({
      :suspendable => "SuspendCapable",
      :rrestartable => "RemoteRestartCapable"
    }.freeze)

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
    def capabilities
      xml.get_elements("VirtualIOServerCapabilities/*").map do |elem|
        elem.name if elem.text&.strip == "true"
      end.compact.concat(super)
    end

    def pvs
      collection_of("PhysicalVolumes", "PhysicalVolume")
    end

    def vg_uuids
      uuids_from_links("StoragePools")
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

  # Volume Group information
  class VolumeGroup < AbstractRest
    ATTRS = {
      :udid => "UniqueDeviceID",
      :size => "AvailableSize", # in GiB
      :dev_count => "BackingDeviceCount",
      :free_space => "FreeSpace", # in GiB
      :capacity => "GroupCapacity",
      :name => "GroupName",
      :serial => "GroupSerialID",
      :state => "GroupState",
      :max_lvs => "MaximumLogicalVolumes"
    }.freeze

    def reps
      collection_of("MediaRepositories", "VirtualMediaRepository")
    end

    def pvs
      collection_of("PhysicalVolumes", "PhysicalVolume")
    end

    def lvs
      collection_of("VirtualDisks", "VirtualDisk")
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
      :capacity => "VolumeCapacity", # in MiB
      :name => "VolumeName",
      :is_fc => "IsFibreChannelBacked",
      :is_iscsi => "IsISCSIBacked",
      :udid => "VolumeUniqueID"
    }.freeze

    def label
      str = singleton("StorageLabel")
      Base64.decode64(str) unless str.nil?
    end

    def page83
      str = singleton("DescriptorPage83")
      Base64.decode64(str) unless str.nil?
    end
  end

  # Logical Volume information
  class VirtualDisk < VirtualSCSIStorage
    ATTRS = {
      :name => "DiskName",
      :label => "DiskLabel",
      :capacity => "DiskCapacity", # in GiB
      :psize => "PartitionSize",
      :udid => "UniqueDeviceID"
    }.freeze

    def vg_uuid
      href = singleton("VolumeGroup", "href")
      uuid_from_href(href) unless href.nil?
    end
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

    def vswitch_href=(href)
      xml.add_element("AssociatedVirtualSwitch").add_element("link", "href" => href, "rel" => "related")
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

  # Shared Memory Pool
  class SharedMemoryPool < AbstractRest
    ATTRS = {
      :pool_mb => "CurrentPoolMemory",
      :available_mb => "CurrentAvailablePoolMemory",
      :max_mb => "CurrentMaximumPoolMemory",
      :sys_mb =>"SystemFirmwarePoolMemory",
      :pool_id => "PoolID",
      :dedup => "MemoryDeduplicationEnabled"
    }.freeze

    def paging_vios_uuids
      ["PagingServicePartitionOne", "PagingServicePartitionTwo"].map do |attr|
        if (vios_href = singleton(attr, "href"))
          uuid_from_href(vios_href)
        end
      end
    end

    def lpar_uuids
      REXML::XPath.match(xml, "PagingDevices/ReservedStorageDevice").map do |dev|
        if (lpar = dev.elements["AssociatedLogicalPartition"])
          uuid_from_href(lpar.attributes["href"])
        end
      end.compact
    end

    def sys_uuid
      uuid_from_href(href, -3)
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
end
