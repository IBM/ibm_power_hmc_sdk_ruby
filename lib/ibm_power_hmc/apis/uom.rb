# frozen_string_literal: true

require 'erb'

module IbmPowerHmc
  class Connection
    ##
    # @!method management_console
    # Retrieve information about the management console.
    # @return [IbmPowerHmc::ManagementConsole] The management console.
    def management_console
      method_url = "/rest/api/uom/ManagementConsole"
      response = request(:get, method_url)
      # This request returns a feed with a single entry.
      FeedParser.new(response.body).objects(:ManagementConsole).first
    end

    ##
    # @!method managed_systems(search = nil, group_name = nil)
    # Retrieve the list of systems managed by the HMC.
    # @param search [String] The optional search criteria.
    # @param group_name [String] The extended group attributes.
    # @return [Array<IbmPowerHmc::ManagedSystem>] The list of managed systems.
    def managed_systems(search = nil, group_name = nil)
      method_url = "/rest/api/uom/ManagedSystem"
      method_url += "/search/(#{ERB::Util.url_encode(search)})" unless search.nil?
      method_url += "?group=#{group_name}" unless group_name.nil?
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:ManagedSystem)
    end

    ##
    # @!method managed_system(sys_uuid, group_name = nil)
    # Retrieve information about a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::ManagedSystem] The managed system.
    def managed_system(sys_uuid, group_name = nil)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}"
      method_url += "?group=#{group_name}" unless group_name.nil?
      response = request(:get, method_url)
      Parser.new(response.body).object(:ManagedSystem)
    end

    ##
    # @!method managed_systems_quick
    # Retrieve the list of systems managed by the HMC (using Quick API).
    # @return [Array<Hash>] The list of managed systems.
    def managed_systems_quick
      method_url = "/rest/api/uom/ManagedSystem/quick/All"
      response = request(:get, method_url)
      JSON.parse(response.body)
    end

    ##
    # @!method managed_system_quick(sys_uuid, property = nil)
    # Retrieve information about a managed system (using Quick API).
    # @param sys_uuid [String] The UUID of the managed system.
    # @param property [String] The quick property name (optional).
    # @return [Hash] The managed system.
    def managed_system_quick(sys_uuid, property = nil)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/quick"
      method_url += "/#{property}" unless property.nil?
      response = request(:get, method_url)
      JSON.parse(response.body)
    end

    ##
    # @!method lpars(sys_uuid = nil, search = nil, group_name = nil)
    # Retrieve the list of logical partitions managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param search [String] The optional search criteria.
    # @param group_name [String] The extended group attributes.
    # @return [Array<IbmPowerHmc::LogicalPartition>] The list of logical partitions.
    def lpars(sys_uuid = nil, search = nil, group_name = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition"
        method_url += "/search/(#{ERB::Util.url_encode(search)})" unless search.nil?
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/LogicalPartition"
      end
      method_url += "?group=#{group_name}" unless group_name.nil?
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:LogicalPartition)
    end

    ##
    # @!method lpar(lpar_uuid, sys_uuid = nil, group_name = nil)
    # Retrieve information about a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::LogicalPartition] The logical partition.
    def lpar(lpar_uuid, sys_uuid = nil, group_name = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/LogicalPartition/#{lpar_uuid}"
      end
      method_url += "?group=#{group_name}" unless group_name.nil?
      response = request(:get, method_url)
      Parser.new(response.body).object(:LogicalPartition)
    end

    ##
    # @!method lpars_quick(sys_uuid = nil)
    # Retrieve the list of logical partitions managed by the HMC (using Quick API).
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [Array<Hash>] The list of logical partitions.
    def lpars_quick(sys_uuid = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition/quick/All"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/LogicalPartition/quick/All"
      end
      response = request(:get, method_url)
      JSON.parse(response.body)
    end

    ##
    # @!method lpar_quick_property(lpar_uuid, property_name)
    # Retrieve a quick property of a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param property_name [String] The quick property name.
    # @return [String] The quick property value.
    def lpar_quick_property(lpar_uuid, property_name)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/quick/#{property_name}"

      response = request(:get, method_url)
      response.body[1..-2]
    end

    ##
    # @!method lpar_migrate_validate(lpar_uuid, target_sys_name, sync = true)
    # Validate if a logical partition can be migrated to another managed system.
    # @raise [IbmPowerHmc::JobFailed] if validation fails
    # @param lpar_uuid [String] The UUID of the logical partition to migrate.
    # @param target_sys_name [String] The managed system to migrate partition to.
    # @param sync [Boolean] Start the job and wait for its completion.
    def lpar_migrate_validate(lpar_uuid, target_sys_name, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/MigrateValidate"
      params = {
        "TargetManagedSystemName" => target_sys_name
      }
      HmcJob.new(self, method_url, "MigrateValidate", "LogicalPartition", params).tap do |job|
        job.run if sync
      end
    end

    ##
    # @!method lpar_migrate(lpar_uuid, target_sys_name, sync = true)
    # Migrate a logical partition to another managed system.
    # @param lpar_uuid [String] The UUID of the logical partition to migrate.
    # @param target_sys_name [String] The managed system to migrate partition to.
    # @param sync [Boolean] Start the job and wait for its completion.
    def lpar_migrate(lpar_uuid, target_sys_name, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/Migrate"
      params = {
        "TargetManagedSystemName" => target_sys_name
      }
      HmcJob.new(self, method_url, "Migrate", "LogicalPartition", params).tap do |job|
        job.run if sync
      end
    end

    ##
    # @!method lpar_delete(lpar_uuid)
    # Delete a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition to delete.
    def lpar_delete(lpar_uuid)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}"
      request(:delete, method_url)
      # Returns HTTP 204 if ok
    end

    ##
    # @!method vioses(sys_uuid = nil, search = nil, group_name = nil, permissive = true)
    # Retrieve the list of virtual I/O servers managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param search [String] The optional search criteria.
    # @param group_name [String] The extended group attributes.
    # @param permissive [Boolean] Skip virtual I/O servers that have error conditions.
    # @return [Array<IbmPowerHmc::VirtualIOServer>] The list of virtual I/O servers.
    def vioses(sys_uuid = nil, search = nil, group_name = nil, permissive = true)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer"
        method_url += "/search/(#{ERB::Util.url_encode(search)})" unless search.nil?
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer"
      end
      query = {}
      query["group"] = group_name unless group_name.nil?
      query["ignoreError"] = "true" if permissive
      method_url += "?" + query.map { |h| h.join("=") }.join("&") unless query.empty?

      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:VirtualIOServer)
    end

    ##
    # @!method vios(vios_uuid, sys_uuid = nil, group_name = nil)
    # Retrieve information about a virtual I/O server.
    # @param vios_uuid [String] The UUID of the virtual I/O server.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::VirtualIOServer] The virtual I/O server.
    def vios(vios_uuid, sys_uuid = nil, group_name = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer/#{vios_uuid}"
      end
      method_url += "?group=#{group_name}" unless group_name.nil?
      response = request(:get, method_url)
      Parser.new(response.body).object(:VirtualIOServer)
    end

    ##
    # @!method vioses_quick(sys_uuid = nil)
    # Retrieve the list of virtual I/O servers managed by the HMC (using Quick API).
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [Array<Hash>] The list of virtual I/O servers.
    def vioses_quick(sys_uuid = nil)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer/quick/All"
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer/quick/All"
      end
      response = request(:get, method_url)
      JSON.parse(response.body)
    end

    ##
    # @!method groups
    # Retrieve the list of groups defined on the HMC.
    # A logical partition, a virtual I/O server or a managed system can be
    # associated with multiple group tags.
    # @return [Array<IbmPowerHmc::Group>] The list of groups.
    def groups
      method_url = "/rest/api/uom/Group"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:Group)
    end

    ##
    # @!method virtual_switches(sys_uuid)
    # Retrieve the list of virtual switches from a specified managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [Array<IbmPowerHmc::VirtualSwitch>] The list of virtual switches.
    def virtual_switches(sys_uuid)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualSwitch"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:VirtualSwitch)
    end

    ##
    # @!method virtual_switch(vswitch_uuid, sys_uuid)
    # Retrieve information about a virtual switch.
    # @param vswitch_uuid [String] The UUID of the virtual switch.
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [IbmPowerHmc::VirtualSwitch] The virtual switch.
    def virtual_switch(vswitch_uuid, sys_uuid)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualSwitch/#{vswitch_uuid}"
      response = request(:get, method_url)
      Parser.new(response.body).object(:VirtualSwitch)
    end

    ##
    # @!method virtual_networks(sys_uuid)
    # Retrieve the list of virtual networks from a specified managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [Array<IbmPowerHmc::VirtualNetwork>] The list of virtual networks.
    def virtual_networks(sys_uuid)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualNetwork"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:VirtualNetwork)
    end

    ##
    # @!method virtual_network(vnet_uuid, sys_uuid)
    # Retrieve information about a virtual network.
    # @param vnet_uuid [String] The UUID of the virtual network.
    # @param sys_uuid [String] The UUID of the managed system.
    # @return [IbmPowerHmc::VirtualNetwork] The virtual network.
    def virtual_network(vnet_uuid, sys_uuid)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualNetwork/#{vnet_uuid}"
      response = request(:get, method_url)
      Parser.new(response.body).object(:VirtualNetwork)
    end

    ##
    # @!method network_adapter_lpar(lpar_uuid, netadap_uuid = nil)
    # Retrieve one or all virtual ethernet network adapters attached to a logical partition.
    # @param lpar_uuid [String] UUID of the logical partition.
    # @param netadap_uuid [String] UUID of the adapter to match (returns all adapters if omitted).
    # @return [Array<IbmPowerHmc::ClientNetworkAdapter>, IbmPowerHmc::ClientNetworkAdapter] The list of network adapters.
    def network_adapter_lpar(lpar_uuid, netadap_uuid = nil)
      network_adapter("LogicalPartition", lpar_uuid, netadap_uuid)
    end

    ##
    # @!method network_adapter_vios(vios_uuid, netadap_uuid = nil)
    # Retrieve one or all virtual ethernet network adapters attached to a Virtual I/O Server.
    # @param vios_uuid [String] UUID of the Virtual I/O Server.
    # @param netadap_uuid [String] UUID of the adapter to match (returns all adapters if omitted).
    # @return [Array<IbmPowerHmc::ClientNetworkAdapter>, IbmPowerHmc::ClientNetworkAdapter] The list of network adapters.
    def network_adapter_vios(vios_uuid, netadap_uuid = nil)
      network_adapter("VirtualIOServer", vios_uuid, netadap_uuid)
    end

    def network_adapter(obj_type, lpar_uuid, netadap_uuid)
      if netadap_uuid.nil?
        method_url = "/rest/api/uom/#{obj_type}/#{lpar_uuid}/ClientNetworkAdapter"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:ClientNetworkAdapter)
      else
        method_url = "/rest/api/uom/#{obj_type}/#{lpar_uuid}/ClientNetworkAdapter/#{netadap_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:ClientNetworkAdapter)
      end
    end
    private :network_adapter

    ##
    # @!method sriov_elp_lpar(lpar_uuid, sriov_elp_uuid = nil)
    # Retrieve one or all SR-IOV ethernet logical ports attached to a logical partition.
    # @param lpar_uuid [String] UUID of the logical partition.
    # @param sriov_elp_uuid [String] UUID of the port to match (returns all ports if omitted).
    # @return [Array<IbmPowerHmc::SRIOVEthernetLogicalPort>, IbmPowerHmc::SRIOVEthernetLogicalPort] The list of ports.
    def sriov_elp_lpar(lpar_uuid, sriov_elp_uuid = nil)
      sriov_elp("LogicalPartition", lpar_uuid, sriov_elp_uuid)
    end

    ##
    # @!method sriov_elp_vios(vios_uuid, sriov_elp_uuid = nil)
    # Retrieve one or all SR-IOV ethernet logical ports attached to a Virtual I/O Server.
    # @param vios_uuid [String] UUID of the Virtual I/O Server.
    # @param sriov_elp_uuid [String] UUID of the port to match (returns all ports if omitted).
    # @return [Array<IbmPowerHmc::SRIOVEthernetLogicalPort>, IbmPowerHmc::SRIOVEthernetLogicalPort] The list of ports.
    def sriov_elp_vios(vios_uuid, sriov_elp_uuid = nil)
      sriov_elp("VirtualIOServer", vios_uuid, sriov_elp_uuid)
    end

    def sriov_elp(obj_type, lpar_uuid, sriov_elp_uuid)
      if sriov_elp_uuid.nil?
        method_url = "/rest/api/uom/#{obj_type}/#{lpar_uuid}/SRIOVEthernetLogicalPort"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:SRIOVEthernetLogicalPort)
      else
        method_url = "/rest/api/uom/#{obj_type}/#{lpar_uuid}/SRIOVEthernetLogicalPort/#{sriov_elp_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:SRIOVEthernetLogicalPort)
      end
    end
    private :sriov_elp

    ##
    # @!method vnic_dedicated(lpar_uuid, vnic_uuid = nil)
    # Retrieve one or all dedicated virtual network interface controller (vNIC) attached to a logical partition.
    # @param lpar_uuid [String] UUID of the logical partition.
    # @param vnic_uuid [String] UUID of the vNIC to match (returns all vNICs if omitted).
    # @return [Array<IbmPowerHmc::VirtualNICDedicated>, IbmPowerHmc::VirtualNICDedicated] The list of vNICs.
    def vnic_dedicated(lpar_uuid, vnic_uuid = nil)
      if vnic_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/VirtualNICDedicated"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:VirtualNICDedicated)
      else
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/VirtualNICDedicated/#{vnic_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:VirtualNICDedicated)
      end
    end

    ##
    # @!method vscsi_client_adapter(lpar_uuid, adap_uuid = nil)
    # Retrieve one or all virtual SCSI storage client adapters attached to a logical partition.
    # @param lpar_uuid [String] UUID of the logical partition.
    # @param adap_uuid [String] UUID of the adapter to match (returns all adapters if omitted).
    # @return [Array<IbmPowerHmc::VirtualSCSIClientAdapter>, IbmPowerHmc::VirtualSCSIClientAdapter] The list of storage adapters.
    def vscsi_client_adapter(lpar_uuid, adap_uuid = nil)
      if adap_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/VirtualSCSIClientAdapter"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:VirtualSCSIClientAdapter)
      else
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/VirtualSCSIClientAdapter/#{adap_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:VirtualSCSIClientAdapter)
      end
    end

    ##
    # @!method vfc_client_adapter(lpar_uuid, adap_uuid = nil)
    # Retrieve one or all virtual Fibre Channel storage client adapters attached to a logical partition.
    # @param lpar_uuid [String] UUID of the logical partition.
    # @param adap_uuid [String] UUID of the adapter to match (returns all adapters if omitted).
    # @return [Array<IbmPowerHmc::VirtualFibreChannelClientAdapter>, IbmPowerHmc::VirtualFibreChannelClientAdapter] The list of storage adapters.
    def vfc_client_adapter(lpar_uuid, adap_uuid = nil)
      if adap_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/VirtualFibreChannelClientAdapter"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:VirtualFibreChannelClientAdapter)
      else
        method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/VirtualFibreChannelClientAdapter/#{adap_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:VirtualFibreChannelClientAdapter)
      end
    end

    ##
    # @!method clusters(permissive = true)
    # Retrieve the list of clusters managed by the HMC.
    # @param permissive [Boolean] Ignore errors generated from bad clusters.
    # @return [Array<IbmPowerHmc::Cluster>] The list of clusters.
    def clusters(permissive = true)
      method_url = "/rest/api/uom/Cluster#{'?ignoreError=true' if permissive}"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:Cluster)
    end

    ##
    # @!method cluster(cl_uuid)
    # Retrieve information about a cluster.
    # @param cl_uuid [String] The UUID of the cluster.
    # @return [IbmPowerHmc::Cluster] The cluster.
    def cluster(cl_uuid)
      method_url = "/rest/api/uom/Cluster/#{cl_uuid}"
      response = request(:get, method_url)
      Parser.new(response.body).object(:Cluster)
    end

    ##
    # @!method ssps(permissive = true)
    # Retrieve the list of shared storage pools managed by the HMC.
    # @param permissive [Boolean] Ignore errors generated from bad clusters.
    # @return [Array<IbmPowerHmc::SharedStoragePool>] The list of shared storage pools.
    def ssps(permissive = true)
      method_url = "/rest/api/uom/SharedStoragePool#{'?ignoreError=true' if permissive}"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:SharedStoragePool)
    end

    ##
    # @!method ssp(ssp_uuid)
    # Retrieve information about a shared storage pool.
    # @param ssp_uuid [String] The UUID of the shared storage pool.
    # @return [IbmPowerHmc::SharedStoragePool] The shared storage pool.
    def ssp(ssp_uuid)
      method_url = "/rest/api/uom/SharedStoragePool/#{ssp_uuid}"
      response = request(:get, method_url)
      Parser.new(response.body).object(:SharedStoragePool)
    end

    ##
    # @!method tiers(group_name = nil, permissive = true)
    # Retrieve the list of tiers that are part of shared storage pools managed by the HMC.
    # @param group_name [String] The extended group attributes.
    # @param permissive [Boolean] Ignore errors generated from bad clusters.
    # @return [Array<IbmPowerHmc::Tier>] The list of tiers.
    def tiers(group_name = nil, permissive = true)
      method_url = "/rest/api/uom/Tier"
      query = {}
      query["group"] = group_name unless group_name.nil?
      query["ignoreError"] = "true" if permissive
      method_url += "?" + query.map { |h| h.join("=") }.join("&") unless query.empty?
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:Tier)
    end

    ##
    # @!method tier(tier_uuid, ssp_uuid = nil, group_name = nil)
    # Retrieve information about a tier.
    # @param tier_uuid [String] The UUID of the tier.
    # @param ssp_uuid [String] The UUID of the shared storage pool.
    # @param group_name [String] The extended group attributes.
    # @return [IbmPowerHmc::Tier] The tier.
    def tier(tier_uuid, ssp_uuid = nil, group_name = nil)
      if ssp_uuid.nil?
        method_url = "/rest/api/uom/Tier/#{tier_uuid}"
      else
        method_url = "/rest/api/uom/SharedStoragePool/#{ssp_uuid}/Tier/#{tier_uuid}"
      end
      method_url += "?group=#{group_name}" unless group_name.nil?

      response = request(:get, method_url)
      Parser.new(response.body).object(:Tier)
    end

    ##
    # @!method shared_processor_pool(sys_uuid, pool_uuid = nil)
    # Retrieve information about Shared Processor Pools.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param pool_uuid [String] The UUID of the shared processor pool (return all pools if omitted)
    # @return [Array<IbmPowerHmc::SharedProcessorPool>, IbmPowerHmc::SharedProcessorPool] The list of shared processor pools.
    def shared_processor_pool(sys_uuid, pool_uuid = nil)
      if pool_uuid.nil?
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/SharedProcessorPool"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:SharedProcessorPool)
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/SharedProcessorPool/#{pool_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:SharedProcessorPool)
      end
    end

    ##
    # @!method poweron_lpar(lpar_uuid, params = {}, sync = true)
    # Power on a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweron_lpar(lpar_uuid, params = {}, sync = true)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "LogicalPartition", params)
      job.run if sync
      job
    end

    ##
    # @!method poweroff_lpar(lpar_uuid, params = {}, sync = true)
    # Power off a logical partition.
    # @param (see #poweron_lpar)
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweroff_lpar(lpar_uuid, params = {}, sync = true)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "LogicalPartition", params)
      job.run if sync
      job
    end

    ##
    # @!method poweron_vios(vios_uuid, params = {}, sync = true)
    # Power on a virtual I/O server.
    # @param vios_uuid [String] The UUID of the virtual I/O server.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweron_vios(vios_uuid, params = {}, sync = true)
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "VirtualIOServer", params)
      job.run if sync
      job
    end

    ##
    # @!method poweroff_vios(vios_uuid, params = {}, sync = true)
    # Power off a virtual I/O server.
    # @param (see #poweron_vios)
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweroff_vios(vios_uuid, params = {}, sync = true)
      method_url = "/rest/api/uom/VirtualIOServer/#{vios_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "VirtualIOServer", params)
      job.run if sync
      job
    end

    ##
    # @!method poweron_managed_system(sys_uuid, params = {}, sync = true)
    # Power on a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param params [Hash] Job parameters.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweron_managed_system(sys_uuid, params = {}, sync = true)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOn"

      job = HmcJob.new(self, method_url, "PowerOn", "ManagedSystem", params)
      job.run if sync
      job
    end

    ##
    # @!method poweroff_managed_system(sys_uuid, params = {}, sync = true)
    # Power off a managed system.
    # @param (see #poweron_managed_system)
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def poweroff_managed_system(sys_uuid, params = {}, sync = true)
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/PowerOff"

      job = HmcJob.new(self, method_url, "PowerOff", "ManagedSystem", params)
      job.run if sync
      job
    end

    ##
    # @!method remove_connection(hmc_uuid, sys_uuid, sync = true)
    # Remove a managed system from the management console.
    # @param hmc_uuid [String] The UUID of the management console.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def remove_connection(hmc_uuid, sys_uuid, sync = true)
      method_url = "/rest/api/uom/ManagementConsole/#{hmc_uuid}/ManagedSystem/#{sys_uuid}/do/RemoveConnection"

      job = HmcJob.new(self, method_url, "RemoveConnection", "ManagedSystem")
      job.run if sync
      job
    end

    ##
    # @!method chcomgmt(sys_uuid, status)
    # Change the co-management settings for a managed system.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param status [String] The new co-management status ("rel", "norm", "keep").
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def chcomgmt(sys_uuid, status)
      operation = status == "rel" ? "ReleaseController" : "RequestController"
      method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/do/#{operation}"

      params = {}
      params["coManagementControllerStatus"] = status unless status == "rel"
      HmcJob.new(self, method_url, operation, "ManagedSystem", params).tap(&:run)
    end

    ##
    # @!method cli_run(hmc_uuid, cmd, sync = true)
    # Run a CLI command on the HMC as a job.
    # @param hmc_uuid [String] The UUID of the management console.
    # @param cmd [String] The command to run.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def cli_run(hmc_uuid, cmd, sync = true)
      method_url = "/rest/api/uom/ManagementConsole/#{hmc_uuid}/do/CLIRunner"

      params = {
        "cmd" => cmd,
        "acknowledgeThisAPIMayGoAwayInTheFuture" => "true",
      }
      job = HmcJob.new(self, method_url, "CLIRunner", "ManagementConsole", params)
      job.run if sync
      job
    end

    ##
    # @!method grow_lu(cl_uuid, lu_uuid, capacity)
    # Increase the size of a logical unit in a cluster.
    # @param cl_uuid [String] The UUID of the cluster.
    # @param lu_uuid [String] The UUID of the logical unit.
    # @param capacity [Float] The new logical unit size (in GB).
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def grow_lu(cl_uuid, lu_uuid, capacity)
      method_url = "/rest/api/uom/Cluster/#{cl_uuid}/do/GrowLogicalUnit"

      params = {
        "LogicalUnitUDID" => lu_uuid,
        "Capacity" => capacity
      }
      HmcJob.new(self, method_url, "GrowLogicalUnit", "Cluster", params).tap(&:run)
    end

    ##
    # @!method next_events(wait = true)
    # Retrieve a list of events that occured since last call.
    # @param wait [Boolean] If no event is available, block until new events occur.
    # @return [Array<IbmPowerHmc::Event>] The list of events.
    def next_events(wait = true)
      method_url = "/rest/api/uom/Event"

      response = nil
      loop do
        response = request(:get, method_url)
        # The HMC waits 10 seconds before returning 204 if there is no event.
        # There is a hidden "?timeout=X" option but it does not always work.
        # It will return "REST026C Maximum number of event requests exceeded"
        # after a while.
        break if response.code != 204 || !wait
      end
      FeedParser.new(response.body).objects(:Event).map do |e|
        data = e.data.split("/") unless e.data.nil?
        if !data.nil? && data.length >= 2 && data[-2].eql?("UserTask")
          e.usertask = usertask(data.last)
        end
        e
      end.compact
    end
  end
end
