defmodule Deployer.Status.ApplicationTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Nodes, as: FixtureNodes
  alias Deployer.Status.Application, as: StatusApp
  alias Deployer.Status.Version
  alias Foundation.Catalog
  alias Foundation.Common
  alias Foundation.Fixture.Catalog, as: CatalogFixture

  setup do
    CatalogFixture.cleanup()

    release = %Deployer.Release.Version{
      version: "1.0.0",
      hash: "ABC",
      pre_commands: []
    }

    attrs = [deployment: :full_deployment, deploy_ref: make_ref()]

    node1 = FixtureNodes.test_node("test_app", "abc1")
    node2 = FixtureNodes.test_node("test_app", "abc2")
    node3 = FixtureNodes.test_node("test_app", "abc3")

    StatusApp.set_current_version_map(node1, %{release | version: "1.0.2"}, attrs)
    StatusApp.set_current_version_map(node2, %{release | version: "1.0.1"}, attrs)
    StatusApp.set_current_version_map(node3, %{release | version: "1.0.3"}, attrs)

    %{release: release, attrs: attrs, node1: node1, node2: node2, node3: node3}
  end

  test "current_version_map/1 no version configured", %{node1: node1, node2: node2, node3: node3} do
    CatalogFixture.cleanup()

    assert StatusApp.current_version(node1) == nil
    assert StatusApp.current_version(node2) == nil
    assert StatusApp.current_version(node3) == nil
  end

  test "current_version / current_version_map", %{node1: node1, node2: node2, node3: node3} do
    expected_version_1 = "1.0.2"
    expected_version_2 = "1.0.1"
    expected_version_3 = "1.0.3"
    expected_hash = "ABC"
    expected_deployment = :full_deployment

    assert StatusApp.current_version(node1) == expected_version_1
    assert StatusApp.current_version(node2) == expected_version_2
    assert StatusApp.current_version(node3) == expected_version_3

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_1
           } = StatusApp.current_version_map(node1)

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_2
           } = StatusApp.current_version_map(node2)

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_3
           } = StatusApp.current_version_map(node3)
  end

  test "monitored_app_name/0" do
    assert StatusApp.monitored_app_name() == "testapp"
  end

  test "monitored_app_lang/0" do
    assert StatusApp.monitored_app_lang() == "elixir"
  end

  test "subscribe/0" do
    assert StatusApp.subscribe() == :ok
  end

  test "ghosted_version", %{node1: node1} do
    assert Enum.empty?(StatusApp.ghosted_version_list())

    version_map = StatusApp.current_version_map(node1)

    # Add a version to the ghosted version list
    assert {:ok, _} = StatusApp.add_ghosted_version(version_map)
    assert length(StatusApp.ghosted_version_list()) == 1

    # Try to add the same and check the list didn't increase
    assert {:ok, _} = StatusApp.add_ghosted_version(version_map)
    assert length(StatusApp.ghosted_version_list()) == 1

    # Add another version
    assert {:ok, _} = StatusApp.add_ghosted_version(%{version_map | version: "1.1.1"})
    assert length(StatusApp.ghosted_version_list()) == 2
  end

  test "history_version_list", %{node1: node1, node2: node2, node3: node3} do
    version_list = StatusApp.history_version_list()

    assert length(version_list) == 3

    assert [_] = StatusApp.history_version_list(node1)
    assert [_] = StatusApp.history_version_list(node2)
    assert [_] = StatusApp.history_version_list(node3)

    assert %Version{version: "1.0.3"} = Enum.at(version_list, 0)
    assert %Version{version: "1.0.2"} = Enum.at(version_list, 2)
  end

  test "update monitoring apps with Idle State", %{node1: node1, node2: node2, node3: node3} do
    Deployer.MonitorMock
    |> expect(:state, 3, fn node ->
      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [node1, node2, node3] end)

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.supervisor and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.1" and &1.status == :idle)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.2" and &1.status == :idle)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.3" and &1.status == :idle)
           )
  end

  test "update monitoring apps with running state and otp not connected", %{
    node1: node1,
    node2: node2,
    node3: node3
  } do
    Deployer.MonitorMock
    |> expect(:state, 3, fn node ->
      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :running,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [node1, node2, node3] end)

    Deployer.UpgradeMock
    |> stub(:connect, fn _node -> {:error, :not_connecting} end)

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.supervisor and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.1" and &1.status == :running and &1.otp == :not_connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.2" and &1.status == :running and &1.otp == :not_connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.3" and &1.status == :running and &1.otp == :not_connected)
           )
  end

  test "update monitoring apps with running state and otp connected", %{
    node1: node1,
    node2: node2,
    node3: node3
  } do
    Deployer.MonitorMock
    |> expect(:state, 3, fn node ->
      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :running,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [node1, node2, node3] end)

    Deployer.UpgradeMock
    |> stub(:connect, fn _node -> {:ok, :connected} end)

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.supervisor and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.1" and &1.status == :running and &1.otp == :connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.2" and &1.status == :running and &1.otp == :connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.3" and &1.status == :running and &1.otp == :connected)
           )
  end

  test "update monitoring apps with running state and with ghosted version list", %{
    node1: node1,
    node2: node2,
    node3: node3
  } do
    Deployer.MonitorMock
    |> expect(:state, 3, fn node ->
      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :running,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [node1, node2, node3] end)

    Deployer.UpgradeMock
    |> stub(:connect, fn _node -> {:ok, :connected} end)

    ghosted_version = "1.1.1"
    version_map = StatusApp.current_version_map(1)
    # Add ghosted version
    assert {:ok, _} = StatusApp.add_ghosted_version(%{version_map | version: ghosted_version})

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.supervisor and &1.status == :running and
                 &1.last_ghosted_version == ghosted_version)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.1" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.2" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "test_app" and not &1.supervisor and
                 &1.version == "1.0.3" and &1.status == :running)
           )
  end

  test "Initialize a GenServer and capture its state" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    assert {:ok, _pid} = Deployer.Status.Application.start_link(name: name)

    assert {:ok, []} = Deployer.Status.Application.monitoring(name)
  end

  test "Test set mode configuration to manual [valid version]", %{
    node1: node1,
    node2: node2,
    node3: node3
  } do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn node ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [node1, node2, node3] end)

    assert {:ok, _pid} =
             Deployer.Status.Application.start_link(update_apps_interval: 50, name: name)

    {:ok, _map} = Deployer.Status.Application.set_mode(name, :manual, "1.0.1")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = Deployer.Status.Application.monitoring(name)
    assert Enum.find(monitoring, &(&1.mode == :manual and &1.name == "deployex"))

    assert %{
             mode: :manual,
             manual_version: %Deployer.Status.Version{
               hash: "ABC",
               pre_commands: [],
               version: "1.0.1"
             }
           } = Catalog.config()
  end

  test "Test set mode configuration to manual [valid version] - default name", %{
    node1: node1,
    node2: node2,
    node3: node3
  } do
    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn node ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [node1, node2, node3] end)

    assert {:ok, _pid} =
             Deployer.Status.Application.start_link(update_apps_interval: 50)

    {:ok, _map} = Deployer.Status.Application.set_mode(:manual, "1.0.1")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = Deployer.Status.Application.monitoring()
    assert Enum.find(monitoring, &(&1.mode == :manual and &1.name == "deployex"))

    assert %{
             mode: :manual,
             manual_version: %Deployer.Status.Version{
               hash: "ABC",
               pre_commands: [],
               version: "1.0.1"
             }
           } = Catalog.config()
  end

  test "Test set mode configuration to manual [invalid version]", %{
    node1: node1,
    node2: node2,
    node3: node3
  } do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn node ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [node1, node2, node3] end)

    assert {:ok, _pid} =
             Deployer.Status.Application.start_link(update_apps_interval: 50, name: name)

    {:ok, _map} = Deployer.Status.Application.set_mode(name, :manual, "invalid")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = Deployer.Status.Application.monitoring(name)
    assert Enum.find(monitoring, &(&1.mode == :manual and &1.name == "deployex"))

    assert %{mode: :manual, manual_version: nil} = Catalog.config()
  end

  test "Test set mode configuration to automatic", %{
    node1: node1,
    node2: node2,
    node3: node3
  } do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn node ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        node: node,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [node1, node2, node3] end)

    assert {:ok, _pid} =
             Deployer.Status.Application.start_link(update_apps_interval: 50, name: name)

    {:ok, _map} = Deployer.Status.Application.set_mode(name, :automatic, %{})

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = Deployer.Status.Application.monitoring(name)
    assert Enum.find(monitoring, &(&1.mode == :automatic and &1.name == "deployex"))

    assert %{mode: :automatic, manual_version: nil} = Catalog.config()
  end

  test "update", %{node2: node2} do
    path = Catalog.new_path(node2)
    assert :ok = StatusApp.update(node2)
    refute File.exists?(path)
    assert :ok = StatusApp.update(nil)
  end

  test "clear_new", %{node1: node1} do
    assert :ok = StatusApp.clear_new(node1)
  end
end
