defmodule Sentinel.Watchdog.WatchdogTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  alias Foundation.Catalog
  alias Host.Memory
  alias Sentinel.Fixture.Nodes, as: FixtureNodes
  alias Sentinel.Monitoring.BeamVm
  alias Sentinel.Watchdog.Server, as: WatchdogServer

  @watchdog_data :deployex_watchdog_data

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "start_link/1" do
    name = "#{__MODULE__}-001" |> String.to_atom()

    assert {:ok, _pid} = WatchdogServer.start_link(name: name, watchdog_check_interval: 10_000)
  end

  test "handle_info/2 - update system info - valid source" do
    name = "#{__MODULE__}-002" |> String.to_atom()
    memory_free = 5_000
    memory_total = 100_000

    assert {:ok, pid} = WatchdogServer.start_link(name: name, watchdog_check_interval: 10_000)

    send(
      pid,
      {:update_system_info,
       %Memory{source_node: Node.self(), memory_free: memory_free, memory_total: memory_total}}
    )

    wait_message_processing(name)

    assert [{_, %Memory{memory_free: ^memory_free, memory_total: ^memory_total}}] =
             :ets.lookup(@watchdog_data, {:system_info, :data})
  end

  test "handle_info/2 - update system info - invalid source" do
    name = "#{__MODULE__}-003" |> String.to_atom()
    memory_free = 5_000
    memory_total = 100_000

    assert {:ok, pid} = WatchdogServer.start_link(name: name, watchdog_check_interval: 10_000)

    send(
      pid,
      {:update_system_info,
       %Memory{source_node: :other@node, memory_free: memory_free, memory_total: memory_total}}
    )

    wait_message_processing(name)
    assert [{_, nil}] = :ets.lookup(@watchdog_data, {:system_info, :data})
  end

  test "handle_info/2 - update application statistics - valid source" do
    name = "#{__MODULE__}-004" |> String.to_atom()

    node = FixtureNodes.test_node(1) |> String.to_atom()

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 100,
      atom_limit: 2_000,
      atom_count: 200,
      process_limit: 3_000,
      process_count: 300
    }

    assert {:ok, pid} = WatchdogServer.start_link(name: name, watchdog_check_interval: 10_000)

    assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :port})
    assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :atom})

    assert [{_, %{count: nil, limit: nil}}] =
             :ets.lookup(@watchdog_data, {node, :data, :process})

    assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

    send(
      pid,
      {:beam_vm_update_statistics,
       %BeamVm{source_node: Node.self(), statistics: Map.put(%{}, node, node_statistic)}}
    )

    wait_message_processing(name)
    assert [{_, %{count: 100, limit: 1000}}] = :ets.lookup(@watchdog_data, {node, :data, :port})
    assert [{_, %{count: 200, limit: 2000}}] = :ets.lookup(@watchdog_data, {node, :data, :atom})

    assert [{_, %{count: 300, limit: 3000}}] =
             :ets.lookup(@watchdog_data, {node, :data, :process})

    assert [{_, 1_000_000}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

    send(
      pid,
      {:beam_vm_update_statistics,
       %BeamVm{
         source_node: Node.self(),
         statistics:
           Map.put(
             %{},
             node,
             %{
               total_memory: nil,
               port_limit: nil,
               port_count: nil,
               atom_limit: nil,
               atom_count: nil,
               process_limit: nil,
               process_count: nil
             }
           )
       }}
    )

    wait_message_processing(name)
    assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :port})
    assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :atom})

    assert [{_, %{count: nil, limit: nil}}] =
             :ets.lookup(@watchdog_data, {node, :data, :process})

    assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
  end

  test "handle_info/2 - update application statistics - invalid source" do
    name = "#{__MODULE__}-005" |> String.to_atom()

    fake_node = :fake@hostname
    self_node = Node.self()
    expected_nodes = Catalog.expected_nodes() -- [self_node]

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 100,
      atom_limit: 2_000,
      atom_count: 200,
      process_limit: 3_000,
      process_count: 300
    }

    assert {:ok, pid} = WatchdogServer.start_link(name: name, watchdog_check_interval: 10_000)

    send(
      pid,
      {:beam_vm_update_statistics,
       %BeamVm{source_node: self_node, statistics: Map.put(%{}, fake_node, node_statistic)}}
    )

    wait_message_processing(name)

    # Check no changes in the expected nodes
    Enum.each(expected_nodes, fn node ->
      assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :port})
      assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :atom})

      assert [{_, %{count: nil, limit: nil}}] =
               :ets.lookup(@watchdog_data, {node, :data, :process})

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)

    send(
      pid,
      {:beam_vm_update_statistics,
       %BeamVm{source_node: fake_node, statistics: Map.put(%{}, fake_node, node_statistic)}}
    )

    wait_message_processing(name)
    # Check no changes in the expected nodes
    Enum.each(expected_nodes, fn node ->
      assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :port})
      assert [{_, %{count: nil, limit: nil}}] = :ets.lookup(@watchdog_data, {node, :data, :atom})

      assert [{_, %{count: nil, limit: nil}}] =
               :ets.lookup(@watchdog_data, {node, :data, :process})

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)
  end

  test "Monitored applications statistic warning" do
    name = "#{__MODULE__}-005" |> String.to_atom()

    self_node = Node.self()
    node = FixtureNodes.test_node(1) |> String.to_atom()

    assert {:ok, pid} = WatchdogServer.start_link(name: name, watchdog_check_interval: 10_000)

    send(
      pid,
      {:beam_vm_update_statistics,
       %BeamVm{
         source_node: self_node,
         statistics:
           Map.put(%{}, node, %{
             total_memory: 1_000_000,
             port_limit: 1_000,
             port_count: 110,
             atom_limit: 2_000,
             atom_count: 220,
             process_limit: 3_000,
             process_count: 330
           })
       }}
    )

    wait_message_processing(name)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(name)
      end)

    assert message =~ "[#{node}] port threshold exceeded: current 11% > warning 10%."
    assert message =~ "[#{node}] atom threshold exceeded: current 11% > warning 10%."
    assert message =~ "[#{node}] process threshold exceeded: current 11% > warning 10%."

    # Check Alarm raised
    assert [{_, %{warning_log: true}}] = :ets.lookup(@watchdog_data, {node, :config, :port})
    assert [{_, %{warning_log: true}}] = :ets.lookup(@watchdog_data, {node, :config, :atom})

    assert [{_, %{warning_log: true}}] =
             :ets.lookup(@watchdog_data, {node, :config, :process})

    send(
      pid,
      {:beam_vm_update_statistics,
       %BeamVm{
         source_node: self_node,
         statistics:
           Map.put(%{}, node, %{
             total_memory: 1_000_000,
             port_limit: 1_000,
             port_count: 100,
             atom_limit: 2_000,
             atom_count: 200,
             process_limit: 3_000,
             process_count: 300
           })
       }}
    )

    wait_message_processing(name)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(name)
      end)

    assert message =~ "[#{node}] port threshold normalized: current 10% <= warning 10%."
    assert message =~ "[#{node}] atom threshold normalized: current 10% <= warning 10%."
    assert message =~ "[#{node}] process threshold normalized: current 10% <= warning 10%."
    # Check Alarm cleared
    assert [{_, %{warning_log: false}}] = :ets.lookup(@watchdog_data, {node, :config, :port})
    assert [{_, %{warning_log: false}}] = :ets.lookup(@watchdog_data, {node, :config, :atom})

    assert [{_, %{warning_log: false}}] =
             :ets.lookup(@watchdog_data, {node, :config, :process})
  end

  test "Monitored applications statistic - ignore nil data" do
    name = "#{__MODULE__}-005" |> String.to_atom()

    self_node = Node.self()
    node = FixtureNodes.test_node(1) |> String.to_atom()

    assert {:ok, pid} = WatchdogServer.start_link(name: name, watchdog_check_interval: 10_000)

    send(
      pid,
      {:beam_vm_update_statistics,
       %BeamVm{
         source_node: self_node,
         statistics:
           Map.put(%{}, node, %{
             total_memory: nil,
             port_limit: nil,
             port_count: 110,
             atom_limit: nil,
             atom_count: 220,
             process_limit: nil,
             process_count: 330
           })
       }}
    )

    wait_message_processing(name)

    send(pid, :watchdog_check)

    wait_message_processing(name)

    # Check Alarm raised
    assert [{_, %{warning_log: false}}] = :ets.lookup(@watchdog_data, {node, :config, :port})
    assert [{_, %{warning_log: false}}] = :ets.lookup(@watchdog_data, {node, :config, :atom})

    assert [{_, %{warning_log: false}}] =
             :ets.lookup(@watchdog_data, {node, :config, :process})
  end

  # Note: Fetching the state guarantees that handle_info will be executed and the ETS table will be updated.
  defp wait_message_processing(name) do
    %{expected_nodes: _expected_nodes} = :sys.get_state(name)
  end
end
