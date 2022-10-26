## v0.19.0
* Major code refactoring
* Add `serviceable_events` method
* Add schema definitions for serviceable events
* Add `lpar_delete` method
* Add HttpNotFound exception for 404 errors
## v0.18.0
* Remove deprecated `rename_lpar` method (replaced by `modify_object`)
* Add schema definition for SEA
* Add schema definition for trunk adapters
* Add schema definition for IPInterface
## v0.17.0
* Add extended group attributes to lpars and vioses methods
* Add `lpars_quick` and `vioses_quick` methods
## v0.16.0
* Add timeout parameter for `IbmPowerHmc::Connection`
* Export `modify_object` method
* Add more attributes to ManagementConsole schema definition
* Add schema definitions for more IOAdapters
## v0.15.0
* Add `managed_systems_quick` and `managed_system_quick` methods
## v0.14.0
* Make search parameter a string instead of a hash
* Add `is_classic_hmc_mgmt` and `is_hmc_mgmt_master` to schema definitions
## v0.13.0
* Add `lpar_migrate_validate` and `lpar_migrate` methods
* Add `vscsi_client_adapter` and `vfc_client_adapter` methods
* Add schema definition for SharedProcessorPool
## 0.12.0
* Add permissive parameter to vioses method
* Add draft parameter to templates and `templates_summary` methods
* Add `template_copy` method
* Add `sys_uuid` parameter to `managed_system_pcm_preferences` method
## v0.11.0
* Add `template_check`, `template_transform` and `template_provision` methods
* Add JobFailed exception
* Add vfc, vlans, vscsi setters to schema definition for templates
## v0.10.0
* Add `managed_system_pcm_preferences` method
* Add schema definitions for PCM
## v0.9.0
* Add groups method
* Add SSH public keys to ManagementConsole schema definition
* Add schema definitions for groups
* Add schema definition for SharedFileSystemFile
* Fix parsing of unknown backing devices
## v0.8.0
* Add templates method
## v0.7.0
* Add cluster, SSP and tier methods
* Add template methods
* Add `capture_lpar` method
* Add usertask method
* Add schema definition for IOAdapter
* Add schema definitions for disks
* Add schema definitions for VSCSI and VFC
* Add schema definitions for cluster, SSP and tier
* Add schema definitions for templates
## v0.6.0
* Add SRIOV and VNIC methods
* Add schema definitions for SRIOVEthernetLogicalPort and VirtualNICDedicated
## v0.5.0
* Add `virtual_networks` method for VLANs
* Add schema definitions for VirtualNetwork, VirtualIOAdapter, VirtualEthernetAdapter
## v0.4.0
* Add `network_adapter_lpar` and `network_adapter_vios` methods
* Add `virtual_switches` and `virtual_switch` methods
* Add schema definitions for VirtualSwitch and ClientNetworkAdapter
## v0.3.0
* Add `rename_lpar` method
* Add `remove_connection` method
## v0.2.0
* Add rubocop local overrides
* Add PCM APIs
* Add search parameter
## v0.1.0
* Initial release
