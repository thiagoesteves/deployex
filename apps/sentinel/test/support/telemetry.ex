defmodule Sentinel.Fixture.Telemetry do
  @moduledoc """
  This module will provide Beam Vm Fixtures
  """

  alias ObserverWeb.Telemetry

  def send_update_app_message(pid, source_node, attrs) do
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

    send(
      pid,
      {:metrics_new_data, source_node, "vm.port.total",
       %Telemetry.Data{
         value: statistics.port_count,
         measurements: %{total: statistics.port_count, limit: statistics.port_limit}
       }}
    )

    send(
      pid,
      {:metrics_new_data, source_node, "vm.atom.total",
       %Telemetry.Data{
         value: statistics.atom_count,
         measurements: %{total: statistics.atom_count, limit: statistics.atom_limit}
       }}
    )

    send(
      pid,
      {:metrics_new_data, source_node, "vm.process.total",
       %Telemetry.Data{
         value: statistics.process_count,
         measurements: %{total: statistics.process_count, limit: statistics.process_limit}
       }}
    )

    send(
      pid,
      {:metrics_new_data, source_node, "vm.memory.total",
       %Telemetry.Data{
         value: statistics.total_memory,
         measurements: %{total: statistics.total_memory}
       }}
    )
  end
end
