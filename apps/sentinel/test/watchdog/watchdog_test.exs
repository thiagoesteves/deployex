defmodule Sentinel.Watchdog.WatchdogTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  alias Foundation.Catalog
  alias Sentinel.Fixture.Host, as: FixtureHost
  alias Sentinel.Fixture.Telemetry, as: FixtureTelemetry
  alias Sentinel.Watchdog
  alias Sentinel.Watchdog.Data

  @watchdog_data :deployex_watchdog_data

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "start_link/1" do
    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, _pid} = Watchdog.start_link(watchdog_check_interval: 10_000)
  end

  test "handle_info/2 - update system info - valid source" do
    memory_free = 5_000
    memory_total = 100_000
    memory_used = memory_total - memory_free

    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    send(pid, {:new_deploy, Node.self(), "nonode"})

    FixtureHost.send_update_sys_info_message(pid, Node.self(), memory_free, memory_total)

    wait_message_processing(pid)

    assert %{current: ^memory_used, limit: ^memory_total} = Watchdog.get_system_memory_data()
  end

  test "handle_info/2 - update system info - invalid source" do
    memory_free = 5_000
    memory_total = 100_000

    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    send(pid, {:new_deploy, Node.self(), "nonode"})

    FixtureHost.send_update_sys_info_message(pid, :other@node, memory_free, memory_total)

    wait_message_processing(pid)
    assert %Data{} = Watchdog.get_system_memory_data()
  end

  test "handle_info/2 - update application statistics - valid source" do
    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 100,
      atom_limit: 2_000,
      atom_count: 200,
      process_limit: 3_000,
      process_count: 300
    }

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    send(pid, {:new_deploy, Node.self(), sname})

    assert %Data{} = Watchdog.get_app_data(node, :port)
    assert %Data{} = Watchdog.get_app_data(node, :atom)
    assert %Data{} = Watchdog.get_app_data(node, :process)

    assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)
    assert %Data{current: 100, limit: 1000} = Watchdog.get_app_data(node, :port)
    assert %Data{current: 200, limit: 2000} = Watchdog.get_app_data(node, :atom)
    assert %Data{current: 300, limit: 3000} = Watchdog.get_app_data(node, :process)

    assert [{_, 1_000_000}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

    # Do not update when value=nil
    FixtureTelemetry.send_update_app_message(pid, node, %{})

    wait_message_processing(pid)
    assert %Data{current: 100, limit: 1000} = Watchdog.get_app_data(node, :port)
    assert %Data{current: 200, limit: 2000} = Watchdog.get_app_data(node, :atom)
    assert %Data{current: 300, limit: 3000} = Watchdog.get_app_data(node, :process)

    assert [{_, 1_000_000}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
  end

  test "handle_info/2 - update application statistics - invalid source" do
    fake_sname = Catalog.create_sname("fake_app")
    %{node: fake_node} = Catalog.node_info(fake_sname)

    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)

    monitored_nodes = [node]

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 100,
      atom_limit: 2_000,
      atom_count: 200,
      process_limit: 3_000,
      process_count: 300
    }

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    send(pid, {:new_deploy, Node.self(), sname})

    FixtureTelemetry.send_update_app_message(pid, fake_node, node_statistic)

    wait_message_processing(pid)

    # Check no changes in the expected nodes
    Enum.each(monitored_nodes, fn node ->
      assert %Data{} = Watchdog.get_app_data(node, :port)
      assert %Data{} = Watchdog.get_app_data(node, :atom)
      assert %Data{} = Watchdog.get_app_data(node, :process)

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)

    FixtureTelemetry.send_update_app_message(pid, fake_node, node_statistic)

    wait_message_processing(pid)
    # Check no changes in the expected nodes
    Enum.each(monitored_nodes, fn node ->
      assert %Data{} = Watchdog.get_app_data(node, :port)
      assert %Data{} = Watchdog.get_app_data(node, :atom)
      assert %Data{} = Watchdog.get_app_data(node, :process)

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)
  end

  test "Monitore application - No warning if the statistic is inside the threshold" do
    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 50,
      atom_limit: 1_000,
      atom_count: 50,
      process_limit: 1_000,
      process_count: 50
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message == ""

    # Check Alarm is clear
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :port)
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :atom)
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :process)
  end

  test "Monitore application - statistic warning" do
    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 110,
      atom_limit: 2_000,
      atom_count: 220,
      process_limit: 3_000,
      process_count: 330
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "[#{node}] port threshold exceeded: current 11% > warning 10%."
    assert message =~ "[#{node}] atom threshold exceeded: current 11% > warning 10%."
    assert message =~ "[#{node}] process threshold exceeded: current 11% > warning 10%."

    # Check Alarm raised
    assert %{warning_log_flag: true} = Watchdog.get_app_config(node, :port)
    assert %{warning_log_flag: true} = Watchdog.get_app_config(node, :atom)
    assert %{warning_log_flag: true} = Watchdog.get_app_config(node, :process)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 100,
      atom_limit: 2_000,
      atom_count: 200,
      process_limit: 3_000,
      process_count: 300
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "[#{node}] port threshold normalized: current 10% <= warning 10%."
    assert message =~ "[#{node}] atom threshold normalized: current 10% <= warning 10%."
    assert message =~ "[#{node}] process threshold normalized: current 10% <= warning 10%."
    # Check Alarm cleared
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :port)
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :atom)
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :process)
  end

  test "Monitore application - ignore nil data" do
    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    node_statistic = %{
      total_memory: nil,
      port_limit: nil,
      port_count: 110,
      atom_limit: nil,
      atom_count: 220,
      process_limit: nil,
      process_count: 330
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    send(pid, :watchdog_check)

    wait_message_processing(pid)

    # Check Alarm raised
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :port)
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :atom)
    assert %{warning_log_flag: false} = Watchdog.get_app_config(node, :process)
  end

  test "Monitore application - restart" do
    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)
    monitored_nodes = [node]

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    Deployer.MonitorMock
    |> stub(:restart, fn _node ->
      send(pid, {:nodedown, node})
      :ok
    end)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 210,
      atom_limit: 2_000,
      atom_count: 420,
      process_limit: 3_000,
      process_count: 630
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~
             "[#{node}] port threshold exceeded: current 21% > restart 20%. Initiating restart..."

    assert message =~
             "[#{node}] atom threshold exceeded: current 21% > restart 20%. Initiating restart..."

    assert message =~
             "[#{node}] process threshold exceeded: current 21% > restart 20%. Initiating restart..."

    # Check reset after restart
    Enum.each(monitored_nodes, fn node ->
      assert %Data{} = Watchdog.get_app_data(node, :port)
      assert %Data{} = Watchdog.get_app_data(node, :atom)
      assert %Data{} = Watchdog.get_app_data(node, :process)

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)
  end

  test "Node Up doesn't change any status" do
    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)
    monitored_nodes = [node]

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    # Check data is empty
    Enum.each(monitored_nodes, fn node ->
      assert %Data{} = Watchdog.get_app_data(node, :port)
      assert %Data{} = Watchdog.get_app_data(node, :atom)
      assert %Data{} = Watchdog.get_app_data(node, :process)

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)

    send(pid, {:nodeup, node})

    wait_message_processing(pid)

    # Check data is still empty
    Enum.each(monitored_nodes, fn node ->
      assert %Data{} = Watchdog.get_app_data(node, :port)
      assert %Data{} = Watchdog.get_app_data(node, :atom)
      assert %Data{} = Watchdog.get_app_data(node, :process)

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)
  end

  test "System memory - No warning if the consumed memory is inside the threshold" do
    memory_free = 900_000
    memory_total = 1_000_000
    self_node = Node.self()

    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    node_statistic = %{
      total_memory: 300_000
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message == ""

    # Check Alarm is clear
    assert %{warning_log_flag: false} = Watchdog.get_system_memory_config()
  end

  test "System memory - Warning if the consumed memory is above the warning threshold" do
    memory_free = 890_000
    memory_total = 1_000_000
    self_node = Node.self()

    sname = Catalog.create_sname("test_app")
    %{node: node} = Catalog.node_info(sname)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    node_statistic = %{
      total_memory: 300_000
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "Total Memory threshold exceeded: current 11% > warning 10%."

    # Check Alarm is set
    assert %{warning_log_flag: true} = Watchdog.get_system_memory_config()

    memory_free = 900_000

    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "Total Memory threshold normalized: current 10% <= warning 10%."

    # Check Alarm is clear
    assert %{warning_log_flag: false} = Watchdog.get_system_memory_config()
  end

  test "System memory - Restart if the consumed memory is above the restart threshold" do
    memory_free = 790_000
    memory_total = 1_000_000
    self_node = Node.self()

    sname_1 = Catalog.create_sname("test_app")
    %{node: node_1} = Catalog.node_info(sname_1)
    sname_2 = Catalog.create_sname("test_app")
    %{node: node_2} = Catalog.node_info(sname_2)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname_1, sname_2] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    Deployer.MonitorMock
    |> stub(:restart, fn
      ^sname_1 ->
        send(pid, {:nodedown, node_1})
        :ok

      ^sname_2 ->
        send(pid, {:nodedown, node_2})
        :ok
    end)

    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    FixtureTelemetry.send_update_app_message(pid, node_1, %{total_memory: 300_000})

    FixtureTelemetry.send_update_app_message(pid, node_2, %{total_memory: 350_000})

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~
             "Total Memory threshold exceeded: current 21% > restart 20%. Initiating restart for #{node_2} ..."

    # Check Alarm is clear after Node Down
    assert %{warning_log_flag: false} = Watchdog.get_system_memory_config()

    # Check next app available for restarting is the other node
    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~
             "Total Memory threshold exceeded: current 21% > restart 20%. Initiating restart for #{node_1} ..."

    # Check Alarm is clear after Node Down
    assert %{warning_log_flag: false} = Watchdog.get_system_memory_config()

    # Add node_1 again
    send(pid, {:new_deploy, Node.self(), sname_1})

    # Receive metrics again and ignore node_2, since it is down
    FixtureTelemetry.send_update_app_message(pid, node_1, %{total_memory: 300_000})

    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    FixtureTelemetry.send_update_app_message(pid, node_2, %{total_memory: 350_000})

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~
             "Total Memory threshold exceeded: current 21% > restart 20%. Initiating restart for #{node_1} ..."
  end

  test "System memory - Don't Restart if the consumed memory is above the restart threshold and node memory is not available" do
    memory_free = 790_000
    memory_total = 1_000_000
    self_node = Node.self()

    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message == ""
  end

  # Note: Fetching the state guarantees that handle_info will be executed and the ETS table will be updated.
  defp wait_message_processing(pid) do
    %{monitored_nodes: _monitored_nodes} = :sys.get_state(pid)
  end
end
