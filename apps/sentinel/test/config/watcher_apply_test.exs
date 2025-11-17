defmodule Sentinel.Config.WatcherApplyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Deployer.Engine
  alias Deployer.Engine.Supervisor, as: EngineSupervisor
  alias Sentinel.Fixture.Watcher, as: FixtureWatcher
  alias Deployer.Monitor
  alias Deployer.Monitor.Supervisor, as: MonitorSupervisor
  alias Sentinel.Config.Upgradable
  alias Sentinel.Config.Watcher

  @default_upgradable %Upgradable{
    logs_retention_time_ms: 86_400_000,
    metrics_retention_time_ms: 86_400_000,
    monitoring: [],
    applications: [],
    config_checksum: "current_checksum"
  }

  test "broadcasts config change when applying" do
    with_mocks([
      {Upgradable, [], [from_app_env: fn -> @default_upgradable end]},
      {Engine, [], [init_worker: fn _application -> :ok end]},
      {EngineSupervisor, [], [stop_deployment: fn _name -> :ok end]},
      {Monitor, [], [init_monitor_supervisor: fn _name -> :ok end]},
      {MonitorSupervisor, [], [stop: fn _name -> :ok end]},
      {Engine.Worker, [], [updated_state_values: fn _name, _map_values -> :ok end]},
      {Sentinel.Watchdog, [], [reset_app_statistics: fn _name -> :ok end]},
      {Sentinel.Logs, [], [update_data_retention_period: fn _new_value -> :ok end]},
      {Application, [:passthrough], [put_all_env: fn _config_updates -> :ok end]}
    ]) do
      log =
        capture_log(fn ->
          {:ok, pid} = Watcher.start_link(name: :test_apply_broadcast)
          node = Node.self()

          # Subscribe to config changes
          Watcher.subscribe_apply_new_config()

          pending_changes = FixtureWatcher.build_pending_changes()

          # Set pending config
          :sys.replace_state(pid, fn state ->
            %{
              state
              | pending_config: %Upgradable{},
                pending_changes: pending_changes
            }
          end)

          assert :ok = Watcher.apply_changes(pid)

          # Verify broadcast received
          assert_receive {:watcher_config_apply, ^node, ^pending_changes}, 1000
        end)

      assert log =~ "ConfigWatcher: Removing application: myumbrella"
    end
  end
end
