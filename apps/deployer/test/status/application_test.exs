defmodule Deployer.Status.ApplicationTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Release
  alias Deployer.Status.Application, as: StatusApp
  alias Foundation.Catalog
  alias Foundation.Common
  alias Foundation.Fixture.Catalog, as: CatalogFixture

  setup do
    CatalogFixture.cleanup()

    release = %Release.Version{
      version: "1.0.0",
      hash: "ABC",
      pre_commands: []
    }

    attrs = [deployment: :full_deployment, deploy_ref: make_ref()]

    name_1 = "myelixir"
    name_2 = "myerlang"
    name_3 = "mygleam"

    sname_1 = Catalog.create_sname(name_1)
    sname_2 = Catalog.create_sname(name_2)
    sname_3 = Catalog.create_sname(name_3)

    StatusApp.set_current_version_map(sname_1, %{release | version: "1.0.2"}, attrs)
    StatusApp.set_current_version_map(sname_2, %{release | version: "1.0.1"}, attrs)
    StatusApp.set_current_version_map(sname_3, %{release | version: "1.0.3"}, attrs)

    %{
      release: release,
      attrs: attrs,
      name_1: name_1,
      name_2: name_2,
      name_3: name_3,
      sname_1: sname_1,
      sname_2: sname_2,
      sname_3: sname_3
    }
  end

  test "current_version_map/1 no version configured", %{
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    CatalogFixture.cleanup()

    assert StatusApp.current_version(sname_1) == nil
    assert StatusApp.current_version(sname_2) == nil
    assert StatusApp.current_version(sname_3) == nil
  end

  test "current_version / current_version_map", %{
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    expected_version_1 = "1.0.2"
    expected_version_2 = "1.0.1"
    expected_version_3 = "1.0.3"
    expected_hash = "ABC"
    expected_deployment = :full_deployment

    assert StatusApp.current_version(sname_1) == expected_version_1
    assert StatusApp.current_version(sname_2) == expected_version_2
    assert StatusApp.current_version(sname_3) == expected_version_3

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_1
           } = StatusApp.current_version_map(sname_1)

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_2
           } = StatusApp.current_version_map(sname_2)

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_3
           } = StatusApp.current_version_map(sname_3)
  end

  test "subscribe/0" do
    assert StatusApp.subscribe() == :ok
  end

  test "ghosted_version", %{name_1: name_1, sname_1: sname_1} do
    assert Enum.empty?(StatusApp.ghosted_version_list(name_1))

    version_map = StatusApp.current_version_map(sname_1)

    # Add a version to the ghosted version list
    assert {:ok, _} = StatusApp.add_ghosted_version(version_map)
    assert length(StatusApp.ghosted_version_list(name_1)) == 1

    # Try to add the same and check the list didn't increase
    assert {:ok, _} = StatusApp.add_ghosted_version(version_map)
    assert length(StatusApp.ghosted_version_list(name_1)) == 1

    # Add another version
    assert {:ok, _} = StatusApp.add_ghosted_version(%{version_map | version: "1.1.1"})
    assert length(StatusApp.ghosted_version_list(name_1)) == 2
  end

  test "history_version_list", %{name_1: name_1, name_2: name_2, name_3: name_3} do
    version_list_1 = StatusApp.history_version_list(name_1, [])
    version_list_2 = StatusApp.history_version_list(name_2, [])
    version_list_3 = StatusApp.history_version_list(name_3, [])

    assert length(version_list_1) == 1
    assert length(version_list_2) == 1
    assert length(version_list_3) == 1

    assert [_] = StatusApp.history_version_list(name_1, [])
    assert [_] = StatusApp.history_version_list(name_2, [])
    assert [_] = StatusApp.history_version_list(name_3, [])

    assert %Catalog.Version{version: "1.0.2"} = Enum.at(version_list_1, 0)
    assert %Catalog.Version{version: "1.0.1"} = Enum.at(version_list_2, 0)
    assert %Catalog.Version{version: "1.0.3"} = Enum.at(version_list_3, 0)
  end

  test "update monitoring apps with Idle State", %{
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    Deployer.MonitorMock
    |> expect(:state, 3, fn sname ->
      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [sname_1, sname_2, sname_3] end)

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myerlang" and &1.version == "1.0.1" and &1.status == :idle)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myelixir" and &1.version == "1.0.2" and &1.status == :idle)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "mygleam" and &1.version == "1.0.3" and &1.status == :idle)
           )
  end

  test "update monitoring apps with running state and otp not connected", %{
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    Deployer.MonitorMock
    |> expect(:state, 3, fn sname ->
      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :running,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [sname_1, sname_2, sname_3] end)

    Deployer.UpgradeMock
    |> stub(:connect, fn _node -> {:error, :not_connecting} end)

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myerlang" and &1.version == "1.0.1" and &1.status == :running and
                 &1.otp == :not_connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myelixir" and &1.version == "1.0.2" and &1.status == :running and
                 &1.otp == :not_connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "mygleam" and &1.version == "1.0.3" and &1.status == :running and
                 &1.otp == :not_connected)
           )
  end

  test "update monitoring apps with running state and otp connected", %{
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    Deployer.MonitorMock
    |> expect(:state, 3, fn sname ->
      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :running,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [sname_1, sname_2, sname_3] end)

    Deployer.UpgradeMock
    |> stub(:connect, fn _node -> {:ok, :connected} end)

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myerlang" and &1.version == "1.0.1" and &1.status == :running and
                 &1.otp == :connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myelixir" and &1.version == "1.0.2" and &1.status == :running and
                 &1.otp == :connected)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "mygleam" and &1.version == "1.0.3" and &1.status == :running and
                 &1.otp == :connected)
           )
  end

  test "update monitoring apps with running state and with ghosted version list", %{
    name_1: name_1,
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    Deployer.MonitorMock
    |> expect(:state, 3, fn sname ->
      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :running,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> expect(:list, 1, fn -> [sname_1, sname_2, sname_3] end)

    Deployer.UpgradeMock
    |> stub(:connect, fn _node -> {:ok, :connected} end)

    ghosted_version = "1.1.1"
    version_map = StatusApp.current_version_map(sname_1)
    # Add ghosted version
    assert {:ok, _} = StatusApp.add_ghosted_version(%{version_map | version: ghosted_version})

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    deployex = Enum.find(monitoring, &(&1.name == "deployex"))
    assert deployex.config[name_1].last_ghosted_version == ghosted_version

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myelixir" and &1.version == "1.0.2" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "myerlang" and &1.version == "1.0.1" and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "mygleam" and &1.version == "1.0.3" and &1.status == :running)
           )
  end

  test "Initialize a GenServer and capture its state" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    assert {:ok, _pid} = StatusApp.start_link(name: name)

    assert {:ok, []} = StatusApp.monitoring(name)
  end

  test "Test set mode configuration to manual [valid version]", %{
    name_1: name_1,
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    module_name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn sname ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [sname_1, sname_2, sname_3] end)

    assert {:ok, _pid} = StatusApp.start_link(update_apps_interval: 50, name: module_name)

    {:ok, _map} = StatusApp.set_mode(module_name, name_1, :manual, "1.0.2")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = StatusApp.monitoring(module_name)
    deployex = Enum.find(monitoring, &(&1.name == "deployex"))
    assert deployex.config[name_1].mode == :manual

    assert %{
             mode: :manual,
             manual_version: %Catalog.Version{
               hash: "ABC",
               pre_commands: [],
               version: "1.0.2"
             }
           } = Catalog.config(name_1)
  end

  test "Test set mode configuration to manual [valid version] - default name", %{
    name_1: name_1,
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    module_name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn sname ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [sname_1, sname_2, sname_3] end)

    assert {:ok, _pid} = StatusApp.start_link(update_apps_interval: 50, name: module_name)

    {:ok, _map} = StatusApp.set_mode(module_name, name_1, :manual, "1.0.2")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = StatusApp.monitoring(module_name)
    deployex = Enum.find(monitoring, &(&1.name == "deployex"))
    assert deployex.config[name_1].mode == :manual

    assert %{
             mode: :manual,
             manual_version: %Catalog.Version{
               hash: "ABC",
               pre_commands: [],
               version: "1.0.2"
             }
           } = Catalog.config(name_1)
  end

  test "Test set mode configuration to manual [invalid version]", %{
    name_1: name_1,
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    module_name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn sname ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [sname_1, sname_2, sname_3] end)

    assert {:ok, _pid} = StatusApp.start_link(update_apps_interval: 50, name: module_name)

    {:ok, _map} = StatusApp.set_mode(module_name, name_1, :manual, "invalid")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = StatusApp.monitoring(module_name)
    deployex = Enum.find(monitoring, &(&1.name == "deployex"))
    assert deployex.config[name_1].mode == :manual
    assert %{mode: :manual, manual_version: nil} = Catalog.config(name_1)
  end

  test "Test set mode configuration to automatic", %{
    name_1: name_1,
    sname_1: sname_1,
    sname_2: sname_2,
    sname_3: sname_3
  } do
    module_name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployer.MonitorMock
    |> stub(:state, fn sname ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployer.Monitor{
        current_pid: nil,
        sname: sname,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil
      }
    end)
    |> stub(:list, fn -> [sname_1, sname_2, sname_3] end)

    assert {:ok, _pid} = StatusApp.start_link(update_apps_interval: 50, name: module_name)

    {:ok, _map} = StatusApp.set_mode(module_name, name_1, :automatic, %{})

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = StatusApp.monitoring(module_name)
    deployex = Enum.find(monitoring, &(&1.name == "deployex"))
    assert deployex.config[name_1].mode == :automatic
    assert %{mode: :automatic, manual_version: nil} = Catalog.config(name_1)
  end

  test "update", %{sname_2: sname_2} do
    path = Catalog.new_path(sname_2)
    assert :ok = StatusApp.update(sname_2)
    refute File.exists?(path)
    assert :ok = StatusApp.update(nil)
  end
end
