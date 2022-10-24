# frozen_string_literal: true

module IbmPowerHmc
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
end
