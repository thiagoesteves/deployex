defmodule Sentinel.Watchdog.WatchdogTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  alias Foundation.Catalog
  alias Foundation.Notifications
  alias Sentinel.Fixture.Host, as: FixtureHost
  alias Sentinel.Fixture.Telemetry, as: FixtureTelemetry
  alias Sentinel.Watchdog
  alias Sentinel.Watchdog.Data

  @watchdog_data :deployex_watchdog_data

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  @tag :capture_log
  test "start_link/1" do
    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, _pid} = Watchdog.start_link(watchdog_check_interval: 10_000)
  end

  @tag :capture_log
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

    assert %{current: ^memory_used, limit: ^memory_total} = Watchdog.get_deployex_data(:memory)
  end

  @tag :capture_log
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
    assert %Data{} = Watchdog.get_deployex_data(:memory)
  end

  @tag :capture_log
  test "handle_info/2 - update application statistics - valid source" do
    sname = Catalog.create_sname("myelixir")
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

  @tag :capture_log
  test "handle_info/2 - application statistics - reset config" do
    sname = Catalog.create_sname("myelixir")
    %{node: node, name: name} = Catalog.node_info(sname)

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

    assert %Data{limit: nil, current: nil} = Watchdog.get_app_data(node, :port)
    assert %Data{limit: nil, current: nil} = Watchdog.get_app_data(node, :atom)
    assert %Data{limit: nil, current: nil} = Watchdog.get_app_data(node, :process)

    assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)
    assert %Data{current: 100, limit: 1000} = Watchdog.get_app_data(node, :port)
    assert %Data{current: 200, limit: 2000} = Watchdog.get_app_data(node, :atom)
    assert %Data{current: 300, limit: 3000} = Watchdog.get_app_data(node, :process)

    assert [{_, 1_000_000}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

    # Do not update when value=nil
    Watchdog.reset_app_statistics(name)

    assert %Data{limit: nil, current: nil} = Watchdog.get_app_data(node, :port)
    assert %Data{limit: nil, current: nil} = Watchdog.get_app_data(node, :atom)
    assert %Data{limit: nil, current: nil} = Watchdog.get_app_data(node, :process)

    Watchdog.reset_app_statistics("deployex")

    assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
  end

  @tag :capture_log
  test "handle_info/2 - update application statistics - invalid source" do
    fake_sname = Catalog.create_sname("mygleam")
    %{node: fake_node} = Catalog.node_info(fake_sname)

    sname = Catalog.create_sname("myelixir")
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

  @tag :capture_log
  test "Monitore application - No warning if the statistic is inside the threshold" do
    sname = Catalog.create_sname("myelixir")
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
    assert %{level: :ok} = Watchdog.get_app_config(node, :port)
    assert %{level: :ok} = Watchdog.get_app_config(node, :atom)
    assert %{level: :ok} = Watchdog.get_app_config(node, :process)
  end

  @tag :capture_log
  test "Monitore application - statistic warning" do
    sname = Catalog.create_sname("myelixir")
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

    assert message =~ "[#{node}] port threshold exceeded: current 11% >= warning 10%."
    assert message =~ "[#{node}] atom threshold exceeded: current 11% >= warning 10%."
    assert message =~ "[#{node}] process threshold exceeded: current 11% >= warning 10%."

    # Check Alarm raised
    assert %{level: :warning} = Watchdog.get_app_config(node, :port)
    assert %{level: :warning} = Watchdog.get_app_config(node, :atom)
    assert %{level: :warning} = Watchdog.get_app_config(node, :process)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 90,
      atom_limit: 2_000,
      atom_count: 180,
      process_limit: 3_000,
      process_count: 270
    }

    FixtureTelemetry.send_update_app_message(pid, node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "[#{node}] port threshold normalized: current 9% < warning 10%."
    assert message =~ "[#{node}] atom threshold normalized: current 9% < warning 10%."
    assert message =~ "[#{node}] process threshold normalized: current 9% < warning 10%."
    # Check Alarm cleared
    assert %{level: :ok} = Watchdog.get_app_config(node, :port)
    assert %{level: :ok} = Watchdog.get_app_config(node, :atom)
    assert %{level: :ok} = Watchdog.get_app_config(node, :process)
  end

  @tag :capture_log
  test "Monitore application - ignore nil data" do
    sname = Catalog.create_sname("myelixir")
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
    assert %{level: :ok} = Watchdog.get_app_config(node, :port)
    assert %{level: :ok} = Watchdog.get_app_config(node, :atom)
    assert %{level: :ok} = Watchdog.get_app_config(node, :process)
  end

  @tag :capture_log
  test "Monitore application - restart" do
    sname = Catalog.create_sname("myelixir")
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
             "[#{node}] port threshold exceeded: current 21% >= restart 20%. Initiating restart..."

    assert message =~
             "[#{node}] atom threshold exceeded: current 21% >= restart 20%. Initiating restart..."

    assert message =~
             "[#{node}] process threshold exceeded: current 21% >= restart 20%. Initiating restart..."

    # Check reset after restart
    Enum.each(monitored_nodes, fn node ->
      assert %Data{} = Watchdog.get_app_data(node, :port)
      assert %Data{} = Watchdog.get_app_data(node, :atom)
      assert %Data{} = Watchdog.get_app_data(node, :process)

      assert [{_, nil}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})
    end)
  end

  @tag :capture_log
  test "Node Up doesn't change any status" do
    sname = Catalog.create_sname("myelixir")
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

  @tag :capture_log
  test "Deployex memory - No warning if the consumed memory is inside the threshold" do
    memory_free = 910_000
    memory_total = 1_000_000
    self_node = Node.self()

    sname = Catalog.create_sname("myelixir")
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
    assert %{level: :ok} = Watchdog.get_deployex_config(:memory)
  end

  @tag :capture_log
  test "Deployex memory - Warning if the consumed memory is above the warning threshold" do
    memory_free = 890_000
    memory_total = 1_000_000
    self_node = Node.self()

    sname = Catalog.create_sname("myelixir")
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

    assert message =~ "Total Memory threshold exceeded: current 11% >= warning 10%."

    # Check Alarm is set
    assert %{level: :warning} = Watchdog.get_deployex_config(:memory)

    memory_free = 910_000

    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "Total Memory threshold normalized: current 9% < warning 10%."

    # Check Alarm is clear
    assert %{level: :ok} = Watchdog.get_deployex_config(:memory)
  end

  @tag :capture_log
  test "Deployex memory - Restart if the consumed memory is above the restart threshold" do
    memory_free = 790_000
    memory_total = 1_000_000
    self_node = Node.self()

    sname_1 = Catalog.create_sname("myelixir")
    %{node: node_1} = Catalog.node_info(sname_1)
    sname_2 = Catalog.create_sname("myelixir")
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
             "Total Memory threshold exceeded: current 21% >= restart 20%. Initiating restart..."

    assert message =~ "Restarting #{node_2}, the application consuming the most memory"

    # The memory did not come down, the resource stays critical
    assert %{level: :critical} = Watchdog.get_deployex_config(:memory)

    # Check next app available for restarting is the other node
    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    # The level has not changed, so the restart repeats without repeating the report
    assert message =~ "Restarting #{node_1}, the application consuming the most memory"

    refute message =~ "Total Memory threshold exceeded"

    assert %{level: :critical} = Watchdog.get_deployex_config(:memory)

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

    assert message =~ "Restarting #{node_1}, the application consuming the most memory"
  end

  @tag :capture_log
  test "Deployex memory - Don't Restart if the consumed memory is above the restart threshold and node memory is not available" do
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

    # The host memory is reported even though DeployEx has no application to restart for it
    assert message =~
             "Total Memory threshold exceeded: current 21% >= restart 20%. Initiating restart..."

    assert message =~ "There is no monitored application to restart"

    assert %{level: :critical} = Watchdog.get_deployex_config(:memory)
  end

  @tag :capture_log
  test "Deployex limits - update deployex statistics from its own node" do
    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    assert %Data{limit: nil, current: nil} = Watchdog.get_deployex_data(:port)
    assert %Data{limit: nil, current: nil} = Watchdog.get_deployex_data(:atom)
    assert %Data{limit: nil, current: nil} = Watchdog.get_deployex_data(:process)

    node_statistic = %{
      total_memory: 1_000_000,
      port_limit: 1_000,
      port_count: 100,
      atom_limit: 2_000,
      atom_count: 200,
      process_limit: 3_000,
      process_count: 300
    }

    FixtureTelemetry.send_update_app_message(pid, Node.self(), node_statistic)

    wait_message_processing(pid)

    assert %Data{current: 100, limit: 1000} = Watchdog.get_deployex_data(:port)
    assert %Data{current: 200, limit: 2000} = Watchdog.get_deployex_data(:atom)
    assert %Data{current: 300, limit: 3000} = Watchdog.get_deployex_data(:process)

    # The deployex memory keeps tracking the host memory, it is not fed by the Beam VM series
    assert %Data{limit: nil, current: nil} = Watchdog.get_deployex_data(:memory)

    Watchdog.reset_app_statistics("deployex")

    assert %Data{limit: nil, current: nil} = Watchdog.get_deployex_data(:port)
    assert %Data{limit: nil, current: nil} = Watchdog.get_deployex_data(:atom)
    assert %Data{limit: nil, current: nil} = Watchdog.get_deployex_data(:process)
  end

  @tag :capture_log
  test "Deployex limits - No warning if the statistic is inside the threshold" do
    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    node_statistic = %{
      port_limit: 1_000,
      port_count: 50,
      atom_limit: 1_000,
      atom_count: 50,
      process_limit: 1_000,
      process_count: 50
    }

    FixtureTelemetry.send_update_app_message(pid, Node.self(), node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message == ""

    # Check Alarm is clear
    assert %{level: :ok} = Watchdog.get_deployex_config(:port)
    assert %{level: :ok} = Watchdog.get_deployex_config(:atom)
    assert %{level: :ok} = Watchdog.get_deployex_config(:process)
  end

  @tag :capture_log
  test "Deployex limits - statistic warning" do
    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    node_statistic = %{
      port_limit: 1_000,
      port_count: 110,
      atom_limit: 2_000,
      atom_count: 220,
      process_limit: 3_000,
      process_count: 330
    }

    FixtureTelemetry.send_update_app_message(pid, Node.self(), node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "[deployex] port threshold exceeded: current 11% >= warning 10%."
    assert message =~ "[deployex] atom threshold exceeded: current 11% >= warning 10%."
    assert message =~ "[deployex] process threshold exceeded: current 11% >= warning 10%."

    # Check Alarm raised
    assert %{level: :warning} = Watchdog.get_deployex_config(:port)
    assert %{level: :warning} = Watchdog.get_deployex_config(:atom)
    assert %{level: :warning} = Watchdog.get_deployex_config(:process)

    node_statistic = %{
      port_limit: 1_000,
      port_count: 90,
      atom_limit: 2_000,
      atom_count: 180,
      process_limit: 3_000,
      process_count: 270
    }

    FixtureTelemetry.send_update_app_message(pid, Node.self(), node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~ "[deployex] port threshold normalized: current 9% < warning 10%."
    assert message =~ "[deployex] atom threshold normalized: current 9% < warning 10%."
    assert message =~ "[deployex] process threshold normalized: current 9% < warning 10%."

    # Check Alarm cleared
    assert %{level: :ok} = Watchdog.get_deployex_config(:port)
    assert %{level: :ok} = Watchdog.get_deployex_config(:atom)
    assert %{level: :ok} = Watchdog.get_deployex_config(:process)
  end

  @tag :capture_log
  test "Deployex limits - ignore nil data" do
    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    node_statistic = %{
      port_limit: nil,
      port_count: 110,
      atom_limit: nil,
      atom_count: 220,
      process_limit: nil,
      process_count: 330
    }

    FixtureTelemetry.send_update_app_message(pid, Node.self(), node_statistic)

    wait_message_processing(pid)

    send(pid, :watchdog_check)

    wait_message_processing(pid)

    # Check Alarm is clear
    assert %{level: :ok} = Watchdog.get_deployex_config(:port)
    assert %{level: :ok} = Watchdog.get_deployex_config(:atom)
    assert %{level: :ok} = Watchdog.get_deployex_config(:process)
  end

  @tag :capture_log
  test "Deployex limits - terminate deployex and stop checking the remaining resources" do
    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    # NOTE: port has enable_restart: false in the test config, so it only warns while atom, the
    #       next resource in the list, triggers the termination and halts the process check
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    assert {:ok, pid} =
             Watchdog.start_link(watchdog_check_interval: 10_000, deployex_terminate_delay: 0)

    node_statistic = %{
      port_limit: 1_000,
      port_count: 210,
      atom_limit: 2_000,
      atom_count: 420,
      process_limit: 3_000,
      process_count: 630
    }

    FixtureTelemetry.send_update_app_message(pid, Node.self(), node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    # port has enable_restart: false in the test config, it is reported and left alone
    assert message =~
             "[deployex] port threshold exceeded: current 21% >= restart 20%. Restart is disabled, no action taken."

    assert message =~
             "[deployex] atom threshold exceeded: current 21% >= restart 20%. Initiating restart..."

    assert message =~ "Deployex was requested to terminate, see you soon!!!"

    refute message =~ "[deployex] process threshold"
  end

  @tag :capture_log
  test "Deployex limits - a resource missing from the monitoring section is not evaluated" do
    memory_free = 100_000
    memory_total = 1_000_000
    self_node = Node.self()

    monitoring = Application.fetch_env!(:foundation, :monitoring)

    # Only port remains configured, memory, atom and process are left out of the section
    Application.put_env(:foundation, :monitoring, Keyword.take(monitoring, [:port]))
    on_exit(fn -> Application.put_env(:foundation, :monitoring, monitoring) end)

    sname = Catalog.create_sname("myelixir")
    %{node: node} = Catalog.node_info(sname)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    # Host memory, atom and process usages are all far above their restart thresholds
    FixtureHost.send_update_sys_info_message(pid, self_node, memory_free, memory_total)

    deployex_statistic = %{
      port_limit: 1_000,
      port_count: 10,
      atom_limit: 1_000,
      atom_count: 900,
      process_limit: 1_000,
      process_count: 900
    }

    FixtureTelemetry.send_update_app_message(pid, self_node, deployex_statistic)
    FixtureTelemetry.send_update_app_message(pid, node, %{total_memory: 300_000})

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message == ""

    assert %{enabled: false} = Watchdog.get_deployex_config(:memory)
    assert %{enabled: false} = Watchdog.get_deployex_config(:atom)
    assert %{enabled: false} = Watchdog.get_deployex_config(:process)
    assert %{enabled: true} = Watchdog.get_deployex_config(:port)
  end

  @tag :capture_log
  test "Deployex limits - the critical level is notified even when the restart is disabled" do
    self_node = Node.self()

    Phoenix.PubSub.subscribe(
      Foundation.PubSub,
      Notifications.topic("watchdog_threshold_exceeded")
    )

    Deployer.MonitorMock
    |> expect(:list, fn -> [] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert {:ok, pid} = Watchdog.start_link(watchdog_check_interval: 10_000)

    # Only port is above its restart threshold, and port has enable_restart: false in the test
    # config, so nothing is restarted and DeployEx keeps running
    node_statistic = %{
      port_limit: 1_000,
      port_count: 210,
      atom_limit: 1_000,
      atom_count: 10,
      process_limit: 1_000,
      process_count: 10
    }

    FixtureTelemetry.send_update_app_message(pid, self_node, node_statistic)

    wait_message_processing(pid)

    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message =~
             "[deployex] port threshold exceeded: current 21% >= restart 20%. Restart is disabled, no action taken."

    assert_receive {"watchdog_threshold_exceeded",
                    %{
                      node: ^self_node,
                      type: :port,
                      current_percentage: 21,
                      restart_threshold_percent: 20,
                      action: :no_restart
                    }}

    assert %{level: :critical} = Watchdog.get_deployex_config(:port)

    # A resource that stays at the same level is not reported again
    message =
      capture_log(fn ->
        send(pid, :watchdog_check)

        wait_message_processing(pid)
      end)

    assert message == ""

    refute_receive {"watchdog_threshold_exceeded", _payload}
  end

  # Note: Fetching the state guarantees that handle_info will be executed and the ETS table will be updated.
  defp wait_message_processing(pid) do
    %{monitored_nodes: _monitored_nodes} = :sys.get_state(pid)
  end
end
