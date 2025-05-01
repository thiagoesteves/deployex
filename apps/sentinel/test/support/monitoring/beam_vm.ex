defmodule Sentinel.Fixture.Monitoring.BeamVm do
  @moduledoc """
  This module will provide Beam Vm Fixtures
  """

  alias Sentinel.Monitoring.BeamVm

  def update_app_message(source_node, node, attrs) do
    statistics =
      Map.merge(
        %{
          total_memory: nil,
          port_limit: nil,
          port_count: nil,
          atom_limit: nil,
          atom_count: nil,
          process_limit: nil,
          process_count: nil
        },
        attrs
      )

    message = %BeamVm{
      source_node: source_node,
      statistics: Map.put(%{}, node, statistics)
    }

    {:beam_vm_update_statistics, message}
  end
end
