defmodule Deployex.StatusAppTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Fixture.Storage, as: StorageFixture
  alias Deployex.Status.Application, as: StatusApp
  alias Deployex.Storage

  setup do
    StorageFixture.cleanup()

    release = %Deployex.Release.Version{
      version: "1.0.0",
      hash: "ABC",
      pre_commands: []
    }

    attrs = [deployment: :full_deployment, deploy_ref: make_ref()]

    StatusApp.set_current_version_map(2, %{release | version: "1.0.2"}, attrs)
    StatusApp.set_current_version_map(1, %{release | version: "1.0.1"}, attrs)
    StatusApp.set_current_version_map(3, %{release | version: "1.0.3"}, attrs)
    StatusApp.set_current_version_map(0, %{release | version: "1.0.0"}, attrs)

    %{release: release, attrs: attrs}
  end

  test "current_version_map/1 no version configured" do
    StorageFixture.cleanup()

    assert StatusApp.current_version(1) == nil
    assert StatusApp.current_version(2) == nil
    assert StatusApp.current_version(3) == nil
  end

  test "current_version / current_version_map" do
    expected_version_0 = "1.0.0"
    expected_version_1 = "1.0.1"
    expected_version_2 = "1.0.2"
    expected_version_3 = "1.0.3"
    expected_hash = "ABC"
    expected_deployment = :full_deployment

    assert StatusApp.current_version(0) == expected_version_0
    assert StatusApp.current_version(1) == expected_version_1
    assert StatusApp.current_version(2) == expected_version_2
    assert StatusApp.current_version(3) == expected_version_3

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_0
           } = StatusApp.current_version_map(0)

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_1
           } = StatusApp.current_version_map(1)

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_2
           } = StatusApp.current_version_map(2)

    assert %{
             deployment: ^expected_deployment,
             hash: ^expected_hash,
             pre_commands: [],
             version: ^expected_version_3
           } = StatusApp.current_version_map(3)
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

  test "ghosted_version" do
    assert Enum.empty?(StatusApp.ghosted_version_list())

    version_map = StatusApp.current_version_map(1)

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

  test "history_version_list" do
    version_list = StatusApp.history_version_list()

    assert length(version_list) == 4

    assert [_] = StatusApp.history_version_list(0)
    assert [_] = StatusApp.history_version_list(1)
    assert [_] = StatusApp.history_version_list(2)
    assert [_] = StatusApp.history_version_list(3)

    assert [_] = StatusApp.history_version_list("0")
    assert [_] = StatusApp.history_version_list("1")
    assert [_] = StatusApp.history_version_list("2")
    assert [_] = StatusApp.history_version_list("3")

    assert %{instance: 0} = Enum.at(version_list, 0)
    assert %{instance: 2} = Enum.at(version_list, 3)
  end

  test "update monitoring apps" do
    Deployex.MonitorMock
    |> expect(:state, 3, fn instance ->
      %Deployex.Monitor{
        current_pid: nil,
        instance: instance,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil,
        deploy_ref: :init
      }
    end)

    # No info, update needed
    assert {:noreply, %{monitoring: monitoring}} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert Enum.find(
             monitoring,
             &(&1.name == "deployex" and &1.supervisor and &1.status == :running)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "testapp" and not &1.supervisor and &1.instance == 1 and
                 &1.version == "1.0.1" and &1.status == :idle)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "testapp" and not &1.supervisor and &1.instance == 2 and
                 &1.version == "1.0.2" and &1.status == :idle)
           )

    assert Enum.find(
             monitoring,
             &(&1.name == "testapp" and not &1.supervisor and &1.instance == 3 and
                 &1.version == "1.0.3" and &1.status == :idle)
           )
  end

  test "Initialize a GenServer and capture its state" do
    name = "#{__MODULE__}-status-000" |> String.to_atom()

    assert {:ok, _pid} = Deployex.Status.Application.start_link(name: name)

    assert {:ok, []} = Deployex.Status.Application.monitoring(name)
  end

  test "Test set mode configuration to manual [valid version]" do
    name = "#{__MODULE__}-mode-000" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployex.MonitorMock
    |> stub(:state, fn instance ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployex.Monitor{
        current_pid: nil,
        instance: instance,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil,
        deploy_ref: :init
      }
    end)

    assert {:ok, _pid} =
             Deployex.Status.Application.start_link(update_apps_interval: 50, name: name)

    {:ok, _map} = Deployex.Status.Application.set_mode(name, :manual, "1.0.1")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = Deployex.Status.Application.monitoring(name)
    assert Enum.find(monitoring, &(&1.mode == :manual and &1.name == "deployex"))

    assert %{
             mode: :manual,
             manual_version: %Deployex.Status.Version{
               hash: "ABC",
               pre_commands: [],
               version: "1.0.1"
             }
           } = Storage.config()
  end

  test "Test set mode configuration to manual [invalid version]" do
    name = "#{__MODULE__}-mode-001" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployex.MonitorMock
    |> stub(:state, fn instance ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployex.Monitor{
        current_pid: nil,
        instance: instance,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil,
        deploy_ref: :init
      }
    end)

    assert {:ok, _pid} =
             Deployex.Status.Application.start_link(update_apps_interval: 50, name: name)

    {:ok, _map} = Deployex.Status.Application.set_mode(name, :manual, "invalid")

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = Deployex.Status.Application.monitoring(name)
    assert Enum.find(monitoring, &(&1.mode == :manual and &1.name == "deployex"))

    assert %{mode: :manual, manual_version: nil} = Storage.config()
  end

  test "Test set mode configuration to automatic" do
    name = "#{__MODULE__}-mode-002" |> String.to_atom()

    ref = make_ref()
    pid = self()

    Deployex.MonitorMock
    |> stub(:state, fn instance ->
      called = Process.get("state", 0)
      Process.put("state", called + 1)

      if called > 6 do
        send(pid, {:handle_ref_event, ref})
      end

      %Deployex.Monitor{
        current_pid: nil,
        instance: instance,
        status: :idle,
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil,
        deploy_ref: :init
      }
    end)

    assert {:ok, _pid} =
             Deployex.Status.Application.start_link(update_apps_interval: 50, name: name)

    {:ok, _map} = Deployex.Status.Application.set_mode(name, :automatic, %{})

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert {:ok, monitoring} = Deployex.Status.Application.monitoring(name)
    assert Enum.find(monitoring, &(&1.mode == :automatic and &1.name == "deployex"))

    assert %{mode: :automatic, manual_version: nil} = Storage.config()
  end

  test "update" do
    path = Storage.new_path(1)
    assert :ok = StatusApp.update(1)
    refute File.exists?(path)
  end

  test "clear_new" do
    assert :ok = StatusApp.clear_new(1)
  end
end
