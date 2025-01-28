defmodule Deployex.TelemetryFixtures do
  @moduledoc """
  This module will handle the telemetry fixture
  """

  def build_reporter_vm_memory_total(node, value \\ 70_000.0) do
    %{
      metrics: [
        %TelemetryDeployex.Metrics{
          name: "vm.memory.total",
          version: "0.1.0-rc3",
          value: value,
          unit: " kilobyte",
          info: "",
          tags: %{},
          type: "summary"
        }
      ],
      reporter: node,
      measurements: %{
        atom: 999_681,
        atom_used: 991_582,
        binary: 1_675_976,
        code: 17_108_729,
        ets: 1_733_464,
        processes: 31_075_760,
        processes_used: 31_051_664,
        system: 36_266_035,
        total: 67_341_795
      }
    }
  end

  def build_telemetry_data_vm_total_memory(
        timestamp \\ :rand.uniform(2_000_000_000_000),
        value \\ 70_973.064
      ) do
    %Deployex.Telemetry.Data{
      timestamp: timestamp,
      value: value,
      unit: " kilobyte",
      tags: %{},
      measurements: %{
        atom: 1_294_641,
        atom_used: 1_287_912,
        binary: 1_059_128,
        code: 31_784_038,
        ets: 2_973_664,
        processes: 14_523_720,
        processes_used: 14_439_392,
        system: 56_449_344,
        total: 70_973_064
      }
    }
  end

  def build_telemetry_data(
        timestamp \\ :rand.uniform(2_000_000_000_000),
        value \\ 70_973.064,
        unit \\ ""
      ) do
    %Deployex.Telemetry.Data{
      timestamp: timestamp,
      value: value,
      unit: unit,
      tags: %{},
      measurements: %{}
    }
  end
end
