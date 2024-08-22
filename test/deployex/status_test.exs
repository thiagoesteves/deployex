defmodule Deployex.StatusAppTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.AppConfig
  alias Deployex.Fixture.Storage
  alias Deployex.Status.Application, as: StatusApp

  setup do
    Storage.cleanup()

    release = %{
      "version" => "1.0.0",
      "hash" => "ABC",
      "pre_commands" => []
    }

    attrs = [deployment: "full_deployment", deploy_ref: make_ref()]

    StatusApp.set_current_version_map(2, release, attrs)
    StatusApp.set_current_version_map(1, release, attrs)
    StatusApp.set_current_version_map(3, release, attrs)
    StatusApp.set_current_version_map(0, release, attrs)

    %{release: release, attrs: attrs}
  end

  test "current_version / current_version_map" do
    expected_version = "1.0.0"
    expected_hash = "ABC"
    expected_deployment = "full_deployment"

    assert StatusApp.current_version(0) == expected_version
    assert StatusApp.current_version(1) == expected_version
    assert StatusApp.current_version(2) == expected_version
    assert StatusApp.current_version(3) == expected_version

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = StatusApp.current_version_map(0)

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = StatusApp.current_version_map(1)

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = StatusApp.current_version_map(2)

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = StatusApp.current_version_map(3)
  end

  test "listener_topic/0" do
    assert StatusApp.listener_topic() == "monitoring_app_updated"
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
    assert {:ok, _} = StatusApp.add_ghosted_version(%{version_map | "version" => "1.1.1"})
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

    assert %{"instance" => 0} = Enum.at(version_list, 0)
    assert %{"instance" => 2} = Enum.at(version_list, 3)
  end

  test "update monitoring apps" do
    Deployex.MonitorMock
    |> expect(:state, 3, fn instance ->
      {:ok,
       %Deployex.Monitor.Application{
         current_pid: nil,
         instance: instance,
         status: :idle,
         crash_restart_count: 0,
         start_time: nil,
         deploy_ref: :init
       }}
    end)

    # No info, update needed
    assert {:noreply, monitoring} =
             StatusApp.handle_info(:update_apps, %{monitoring: []})

    assert %{
             monitoring: [
               %Deployex.Status{
                 name: "deployex",
                 instance: 0,
                 version: _,
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: nil,
                 supervisor: true,
                 status: :running,
                 crash_restart_count: 0,
                 uptime: _,
                 last_ghosted_version: "-/-"
               },
               %Deployex.Status{
                 name: "testapp",
                 instance: 1,
                 version: "1.0.0",
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: "full_deployment",
                 supervisor: false,
                 status: :idle,
                 crash_restart_count: 0,
                 uptime: "-/-",
                 last_ghosted_version: nil
               },
               %Deployex.Status{
                 name: "testapp",
                 instance: 2,
                 version: "1.0.0",
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: "full_deployment",
                 supervisor: false,
                 status: :idle,
                 crash_restart_count: 0,
                 uptime: "-/-",
                 last_ghosted_version: nil
               },
               %Deployex.Status{
                 name: "testapp",
                 instance: 3,
                 version: "1.0.0",
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: "full_deployment",
                 supervisor: false,
                 status: :idle,
                 crash_restart_count: 0,
                 uptime: "-/-",
                 last_ghosted_version: nil
               }
             ]
           } = monitoring
  end

  test "Initialize a GenServer and capture its state" do
    name = "#{__MODULE__}-status-000" |> String.to_atom()

    assert {:ok, _pid} = Deployex.Status.Application.start_link(name: name)

    assert {:ok, %{monitoring: [], instances: 3}} = Deployex.Status.Application.state(name)
  end

  test "update" do
    path = AppConfig.new_path(1)
    assert :ok = StatusApp.update(1)
    refute File.exists?(path)
  end

  test "clear_new" do
    assert :ok = StatusApp.clear_new(1)
  end

  test "Adapter function test" do
    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{}} end)
    |> expect(:current_version, fn _instance -> "1.0.0" end)
    |> expect(:current_version_map, fn _instance -> %Deployex.Status{} end)
    |> expect(:listener_topic, fn -> "topic" end)
    |> expect(:set_current_version_map, fn _instance, _map, _list -> :ok end)
    |> expect(:add_ghosted_version, fn map -> {:ok, map} end)
    |> expect(:ghosted_version_list, fn -> [] end)
    |> expect(:history_version_list, fn -> [] end)
    |> expect(:history_version_list, fn _instance -> ["1.0.0"] end)
    |> expect(:clear_new, fn _instance -> :ok end)
    |> expect(:update, fn _instance -> :ok end)

    assert {:ok, %{}} = Deployex.Status.state()
    assert "1.0.0" = Deployex.Status.current_version(1)
    assert %Deployex.Status{} = Deployex.Status.current_version_map(1)
    assert "topic" = Deployex.Status.listener_topic()
    assert :ok = Deployex.Status.set_current_version_map(1, %{}, [])
    assert {:ok, _} = Deployex.Status.add_ghosted_version(%{})
    assert [] = Deployex.Status.ghosted_version_list()
    assert [] = Deployex.Status.history_version_list()
    assert ["1.0.0"] = Deployex.Status.history_version_list(1)
    assert :ok = Deployex.Status.clear_new(1)
    assert :ok = Deployex.Status.update(1)
  end
end
