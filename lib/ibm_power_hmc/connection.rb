# frozen_string_literal: true

# Module for IBM HMC Rest API Client
module IbmPowerHmc
  class Error < StandardError; end

  ##
  # HMC REST Client connection.
  class Connection
    ##
    # @!method initialize(host:, password:, username: "hscroot", port: 12_443, validate_ssl: true)
    # Create a new HMC connection.
    #
    # @param host [String] Hostname of the HMC.
    # @param password [String] Password.
    # @param username [String] User name.
    # @param port [Integer] TCP port number.
    # @param validate_ssl [Boolean] Verify SSL certificates.
    def initialize(host:, password:, username: "hscroot", port: 12_443, validate_ssl: true, timeout: 60)
      @hostname = "#{host}:#{port}"
      @username = username
      @password = password
      @verify_ssl = validate_ssl
      @api_session_token = nil
      @timeout = timeout
    end

    ##
    # @!method logon
    # Establish a trusted session with the Web Services APIs.
    # @return [String] The X-API-Session token.
    def logon
      method_url = "/rest/api/web/Logon"
      headers = {
        :content_type => "application/vnd.ibm.powervm.web+xml; type=LogonRequest"
      }
      doc = REXML::Document.new("")
      doc.add_element("LogonRequest", "schemaVersion" => "V1_1_0")
      doc.root.add_namespace("http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/")
      doc.root.add_element("UserID").text = @username
      doc.root.add_element("Password").text = @password

      @api_session_token = ""
      response = request(:put, method_url, headers, doc.to_s)
      doc = REXML::Document.new(response.body)
      elem = doc.elements["LogonResponse/X-API-Session"]
      raise Error, "LogonResponse/X-API-Session not found" if elem.nil?

      @api_session_token = elem.text
    end

    ##
    # @!method logoff
    # Close the session.
    def logoff
      # Don't want to trigger automatic logon here!
      return if @api_session_token.nil?

      method_url = "/rest/api/web/Logon"
      begin
        request(:delete, method_url)
      rescue
        # Ignore exceptions as this is best effort attempt to log off.
      end
      @api_session_token = nil
    end

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
    # @!method managed_systems(search = {})
    # Retrieve the list of systems managed by the HMC.
    # @param search [Hash] The optional property name and value to match.
    # @return [Array<IbmPowerHmc::ManagedSystem>] The list of managed systems.
    def managed_systems(search = {})
      method_url = "/rest/api/uom/ManagedSystem"
      search.each { |key, value| method_url += "/search/(#{key}==#{value})" }
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:ManagedSystem)
    end

    ##
    # @!method managed_system(lpar_uuid, sys_uuid = nil, group_name = nil)
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
    # @!method lpars(sys_uuid = nil, search = {})
    # Retrieve the list of logical partitions managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param search [Hash] The optional property name and value to match.
    # @return [Array<IbmPowerHmc::LogicalPartition>] The list of logical partitions.
    def lpars(sys_uuid = nil, search = {})
      if sys_uuid.nil?
        method_url = "/rest/api/uom/LogicalPartition"
        search.each { |key, value| method_url += "/search/(#{key}==#{value})" }
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/LogicalPartition"
      end
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
    # @!method rename_lpar(lpar_uuid, new_name)
    # Rename a logical partition.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param new_name [String] The new name of the logical partition.
    def rename_lpar(lpar_uuid, new_name)
      method_url = "/rest/api/uom/LogicalPartition/#{lpar_uuid}"
      modify_object_attributes(method_url, {:name => new_name})
    end

    ##
    # @!method vioses(sys_uuid = nil, search = {}, permissive = true)
    # Retrieve the list of virtual I/O servers managed by the HMC.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param search [Hash] The optional property name and value to match.
    # @param permissive [Boolean] Skip virtual I/O servers that have error conditions.
    # @return [Array<IbmPowerHmc::VirtualIOServer>] The list of virtual I/O servers.
    def vioses(sys_uuid = nil, search = {}, permissive = true)
      if sys_uuid.nil?
        method_url = "/rest/api/uom/VirtualIOServer"
        search.each { |key, value| method_url += "/search/(#{key}==#{value})" }
        method_url += "?ignoreError=true" if permissive
      else
        method_url = "/rest/api/uom/ManagedSystem/#{sys_uuid}/VirtualIOServer"
      end
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

    ##
    # @!method sriov_elp_lpar(lpar_uuid, sriov_elp_uuid = nil)
    # Retrieve one or all SR-IOV ethernet logical ports attached to a logical partition.
    # @param lpar_uuid [String] UUID of the logical partition.
    # @param sriov_elp_uuid [String] UUID of the port to match (returns all ports if omitted).
    # @return [Array<IbmPowerHmc::SRIOVEthernetLogicalPort>, IbmPowerHmc::SRIOVEthernetLogicalPort] The list of ports.
    def sriov_elp_lpar(lpar_uuid, sriov_elp_uuid = nil)
      sriov_ethernet_port("LogicalPartition", lpar_uuid, sriov_elp_uuid)
    end

    ##
    # @!method network_adapter_vios(vios_uuid, sriov_elp_uuid = nil)
    # Retrieve one or all SR-IOV ethernet logical ports attached to a Virtual I/O Server.
    # @param vios_uuid [String] UUID of the Virtual I/O Server.
    # @param sriov_elp_uuid [String] UUID of the port to match (returns all ports if omitted).
    # @return [Array<IbmPowerHmc::SRIOVEthernetLogicalPort>, IbmPowerHmc::SRIOVEthernetLogicalPort] The list of ports.
    def sriov_elp_vios(vios_uuid, sriov_elp_uuid = nil)
      sriov_ethernet_port("VirtualIOServer", vios_uuid, sriov_elp_uuid)
    end

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
    # @!method clusters
    # Retrieve the list of clusters managed by the HMC.
    # @return [Array<IbmPowerHmc::Cluster>] The list of clusters.
    def clusters
      method_url = "/rest/api/uom/Cluster"
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
    # @!method ssps
    # Retrieve the list of shared storage pools managed by the HMC.
    # @return [Array<IbmPowerHmc::SharedStoragePool>] The list of shared storage pools.
    def ssps
      method_url = "/rest/api/uom/SharedStoragePool"
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
    # @!method tiers(group_name = nil)
    # Retrieve the list of tiers that are part of shared storage pools managed by the HMC.
    # @param group_name [String] The extended group attributes.
    # @return [Array<IbmPowerHmc::Tier>] The list of tiers.
    def tiers(group_name = nil)
      method_url = "/rest/api/uom/Tier"
      method_url += "?group=#{group_name}" unless group_name.nil?
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
    # @!method templates_summary(draft = false)
    # Retrieve the list of partition template summaries.
    # @param draft [Boolean] Retrieve draft templates as well
    # @return [Array<IbmPowerHmc::PartitionTemplateSummary>] The list of partition template summaries.
    def templates_summary(draft = false)
      method_url = "/rest/api/templates/PartitionTemplate#{'?draft=false' unless draft}"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:PartitionTemplateSummary)
    end

    ##
    # @!method templates(draft = false)
    # Retrieve the list of partition templates.
    # @param draft [Boolean] Retrieve draft templates as well
    # @return [Array<IbmPowerHmc::PartitionTemplate>] The list of partition templates.
    def templates(draft = false)
      method_url = "/rest/api/templates/PartitionTemplate?detail=full#{'&draft=false' unless draft}"
      response = request(:get, method_url)
      FeedParser.new(response.body).objects(:PartitionTemplate)
    end

    ##
    # @!method template(template_uuid)
    # Retrieve details for a particular partition template.
    # @param template_uuid [String] UUID of the partition template.
    # @return [IbmPowerHmc::PartitionTemplate] The partition template.
    def template(template_uuid)
      method_url = "/rest/api/templates/PartitionTemplate/#{template_uuid}"
      response = request(:get, method_url)
      Parser.new(response.body).object(:PartitionTemplate)
    end

    ##
    # @!method capture_lpar(lpar_uuid, sys_uuid, template_name, sync = true)
    # Capture partition configuration as template.
    # @param lpar_uuid [String] The UUID of the logical partition.
    # @param sys_uuid [String] The UUID of the managed system.
    # @param template_name [String] The name to be given for the new template.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def capture_lpar(lpar_uuid, sys_uuid, template_name, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/do/capture"
      params = {
        "TargetUuid"              => lpar_uuid,
        "NewTemplateName"         => template_name,
        "ManagedSystemUuid"       => sys_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Capture", "PartitionTemplate", params)
      job.run if sync
      job
    end

    ##
    # @!method template_check(template_uuid, target_sys_uuid, sync = true)
    # Start Template Check job (first of three steps to deploy an LPAR from a Template).
    # @param template_uuid [String] The UUID of the Template to deploy an LPAR from.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def template_check(template_uuid, target_sys_uuid, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/#{template_uuid}/do/check"
      params = {
        "TargetUuid"              => target_sys_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Check", "PartitionTemplate", params)
      job.run if sync
      job
    end

    ##
    # @!method template_transform(draft_template_uuid, target_sys_uuid, sync = true)
    # Start Template Transform job (second of three steps to deploy an LPAR from a Template).
    # @param draft_template_uuid [String] The UUID of the Draft Template created by the Template Check job.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def template_transform(draft_template_uuid, target_sys_uuid, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/#{draft_template_uuid}/do/transform"
      params = {
        "TargetUuid"              => target_sys_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Transform", "PartitionTemplate", params)
      job.run if sync
      job
    end

    ##
    # @!method template_deploy(draft_template_uuid, target_sys_uuid, sync = true)
    # Start Template Deploy job (last of three steps to deploy an LPAR from a Template).
    # @param draft_template_uuid [String] The UUID of the Draft Template created by the Template Check job.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param sync [Boolean] Start the job and wait for its completion.
    # @return [IbmPowerHmc::HmcJob] The HMC job.
    def template_deploy(draft_template_uuid, target_sys_uuid, sync = true)
      # Need to include session token in payload so make sure we are logged in
      logon if @api_session_token.nil?
      method_url = "/rest/api/templates/PartitionTemplate/#{draft_template_uuid}/do/deploy"
      params = {
        "TargetUuid"              => target_sys_uuid,
        "TemplateUuid"            => draft_template_uuid,
        "K_X_API_SESSION_MEMENTO" => @api_session_token
      }
      job = HmcJob.new(self, method_url, "Deploy", "PartitionTemplate", params)
      job.run if sync
      job
    end

    ##
    # @!method template_provision(template_uuid, target_sys_uuid, changes)
    # Deploy Logical Partition from a Template (performs Check, Transform and Deploy steps in a single method).
    # @param template_uuid [String] The UUID of the Template to deploy an LPAR from.
    # @param target_sys_uuid [String] The UUID of the Managed System to deploy the LPAR on.
    # @param changes [Hash] Modifications to apply to the Template before deploying Logical Partition.
    # @return [String] The UUID of the deployed Logical Partition.
    def template_provision(template_uuid, target_sys_uuid, changes)
      draft_uuid = template_check(template_uuid, target_sys_uuid).results["TEMPLATE_UUID"]
      template_transform(draft_uuid, target_sys_uuid)
      template_modify(draft_uuid, changes)
      template_deploy(draft_uuid, target_sys_uuid).results["PartitionUuid"]
    end

    ##
    # @!method template(template_uuid, changes)
    # modify_object_attributes wrapper for templates.
    # @param template_uuid [String] UUID of the partition template to modify.
    # @param changes [Hash] Hash of changes to make.
    # @return [IbmPowerHmc::PartitionTemplate] The partition template.
    def template_modify(template_uuid, changes)
      method_url = "/rest/api/templates/PartitionTemplate/#{template_uuid}"
      modify_object_attributes(method_url, changes)
    end

    ##
    # @!method template_copy(template_uuid, new_name)
    # Copy existing template to a new one.
    # @param template_uuid [String] UUID of the partition template to copy.
    # @param new_name [String] Name of the new template.
    # @return [IbmPowerHmc::PartitionTemplate] The new partition template.
    def template_copy(template_uuid, new_name)
      method_url = "/rest/api/templates/PartitionTemplate"
      headers = {
        :content_type => "application/vnd.ibm.powervm.templates+xml;type=PartitionTemplate"
      }
      original = template(template_uuid)
      original.name = new_name
      response = request(:put, method_url, headers, original.xml.to_s)
      Parser.new(response.body).object(:PartitionTemplate)
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
    # @!method next_events(wait = true)
    # Retrieve a list of events that occured since last call.
    # @param wait [Boolean] If no event is available, block until new events occur.
    # @return [Array<IbmPowerHmc::Event>] The list of events.
    def next_events(wait = true)
      method_url = "/rest/api/uom/Event"

      response = nil
      loop do
        response = request(:get, method_url)
        # No need to sleep as the HMC already waits a bit before returning 204
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

    ##
    # @!method usertask(uuid = true)
    # Retrieve details of an event of type "user task".
    # @param uuid [String] UUID of user task.
    # @return [Hash] Hash of user task attributes.
    def usertask(uuid)
      method_url = "/rest/api/ui/UserTask/#{uuid}"
      response = request(:get, method_url)
      j = JSON.parse(response.body)
      if j['status'].eql?("Completed")
        case j['key']
        when "TEMPLATE_PARTITION_SAVE", "TEMPLATE_PARTITION_SAVE_AS", "TEMPLATE_PARTITION_CAPTURE"
          j['template_uuid'] = templates_summary.find { |t| t.name.eql?(j['labelParams'].first) }&.uuid
        end
      end
      j
    end

    ##
    # @!method schema(type)
    # Retrieve the XML schema file for a given object type.
    # @param type [String] The object type (e.g. "LogicalPartition", "inc/Types")
    # @return [REXML::Document] The XML schema file.
    def schema(type)
      method_url = "/rest/api/web/schema/#{type}.xsd"
      response = request(:get, method_url)
      REXML::Document.new(response.body)
    end

    class HttpError < Error
      attr_reader :status, :uri, :reason, :message, :original_exception

      ##
      # @!method initialize(err)
      # Create a new HttpError exception.
      # @param err [RestClient::Exception] The REST client exception.
      def initialize(err)
        super
        @original_exception = err
        @status = err.http_code
        @message = err.message

        # Try to parse body as an HttpErrorResponse.
        unless err.response.nil?
          begin
            resp = Parser.new(err.response.body).object(:HttpErrorResponse)
            @uri = resp.uri
            @reason = resp.reason
            @message = resp.message
          rescue
            # not an XML body
          end
        end
      end

      def to_s
        "msg=\"#{@message}\" status=\"#{@status}\" reason=\"#{@reason}\" uri=#{@uri}"
      end
    end

    ##
    # @!method request(method, url, headers = {}, payload = nil)
    # Perform a REST API request.
    # @param method [String] The HTTP method.
    # @param url [String] The method URL.
    # @param headers [Hash] HTTP headers.
    # @param payload [String] HTTP request payload.
    # @return [RestClient::Response] The response from the HMC.
    def request(method, url, headers = {}, payload = nil)
      logon if @api_session_token.nil?
      reauth = false
      # Check for relative URLs
      url = "https://#{@hostname}#{url}" if url.start_with?("/")
      begin
        headers = headers.merge("X-API-Session" => @api_session_token)
        RestClient::Request.execute(
          :method => method,
          :url => url,
          :verify_ssl => @verify_ssl,
          :payload => payload,
          :headers => headers,
          :timeout => @timeout
        )
      rescue RestClient::Exception => e
        # Do not retry on failed logon attempts.
        if e.http_code == 401 && @api_session_token != "" && !reauth
          # Try to reauth.
          reauth = true
          logon
          retry
        end
        raise HttpError.new(e), "REST request failed"
      end
    end

    private

    # @!method modify_object(method_url, headers = {}, attempts = 5)
    # Modify an object at a specified URI.
    # @param method_url [String] The URL of the object to modify.
    # @param headers [Hash] HTTP headers.
    # @param attempts [Integer] Maximum number of retries.
    # @yield [obj] The object to modify.
    # @yieldparam obj [IbmPowerHmc::AbstractRest] The object to modify.
    def modify_object(method_url, headers = {}, attempts = 5)
      while attempts > 0
        response = request(:get, method_url)
        obj = Parser.new(response.body).object

        yield obj

        # Use ETag to ensure object has not changed.
        headers = headers.merge("If-Match" => obj.etag, :content_type => obj.content_type)
        begin
          request(:post, method_url, headers, obj.xml.to_s)
          break
        rescue HttpError => e
          attempts -= 1
          # Will get 412 ("Precondition Failed") if ETag mismatches.
          raise if e.status != 412 || attempts == 0
        end
      end
    end

    # @!method modify_object_attributes(method_url, changes, headers = {}, attempts = 5)
    # Modify an object at a specified URI.
    # @param method_url [String] The URL of the object to modify.
    # @param changes [Hash] Hash of changes to make. Key is the attribute modify/create (as defined in the AbstractNonRest subclass). A value of nil removes the attribute.
    # @param headers [Hash] HTTP headers.
    # @param attempts [Integer] Maximum number of retries.
    def modify_object_attributes(method_url, changes, headers = {}, attempts = 5)
      modify_object(method_url, headers, attempts) do |obj|
        changes.each do |key, value|
          obj.send("#{key}=", value)
        end
      end
    end

    ##
    # @!method network_adapter(vm_type, lpar_uuid, netadap_uuid)
    # Retrieve one or all virtual ethernet network adapters attached to a Logical Partition or a Virtual I/O Server.
    # @param vm_type [String] "LogicalPartition" or "VirtualIOServer".
    # @param lpar_uuid [String] UUID of the Logical Partition or the Virtual I/O Server.
    # @param netadap_uuid [String] UUID of the adapter to match (returns all adapters if nil).
    # @return [Array<IbmPowerHmc::ClientNetworkAdapter>, IbmPowerHmc::ClientNetworkAdapter] The list of network adapters.
    def network_adapter(vm_type, lpar_uuid, netadap_uuid)
      if netadap_uuid.nil?
        method_url = "/rest/api/uom/#{vm_type}/#{lpar_uuid}/ClientNetworkAdapter"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:ClientNetworkAdapter)
      else
        method_url = "/rest/api/uom/#{vm_type}/#{lpar_uuid}/ClientNetworkAdapter/#{netadap_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:ClientNetworkAdapter)
      end
    end

    ##
    # @!method sriov_ethernet_port(vm_type, lpar_uuid, sriov_elp_uuid)
    # Retrieve one or all SR-IOV Ethernet loical ports attached to a Logical Partition or a Virtual I/O Server.
    # @param vm_type [String] "LogicalPartition" or "VirtualIOServer".
    # @param lpar_uuid [String] UUID of the Logical Partition or the Virtual I/O Server.
    # @param sriov_elp_uuid [String] UUID of the port to match (returns all ports if nil).
    # @return [Array<IbmPowerHmc::SRIOVEthernetLogicalPort>, IbmPowerHmc::SRIOVEthernetLogicalPort] The list of ports.
    def sriov_ethernet_port(vm_type, lpar_uuid, sriov_elp_uuid)
      if sriov_elp_uuid.nil?
        method_url = "/rest/api/uom/#{vm_type}/#{lpar_uuid}/SRIOVEthernetLogicalPort"
        response = request(:get, method_url)
        FeedParser.new(response.body).objects(:SRIOVEthernetLogicalPort)
      else
        method_url = "/rest/api/uom/#{vm_type}/#{lpar_uuid}/SRIOVEthernetLogicalPort/#{sriov_elp_uuid}"
        response = request(:get, method_url)
        Parser.new(response.body).object(:SRIOVEthernetLogicalPort)
      end
    end
  end
end
