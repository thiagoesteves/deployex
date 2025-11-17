defmodule Sentinel.Config.WatcherApplyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Deployer.Engine
  alias Deployer.Engine.Supervisor, as: EngineSupervisor
  alias Deployer.Monitor
  alias Deployer.Monitor.Supervisor, as: MonitorSupervisor
  alias Sentinel.Config.Changes
  alias Sentinel.Config.Upgradable
  alias Sentinel.Config.Watcher

  @default_upgradable %Upgradable{
    logs_retention_time_ms: 86_400_000,
    metrics_retention_time_ms: 86_400_000,
    monitoring: [],
    applications: [],
    config_checksum: "current_checksum"
  }

  @summary_with_all_possible_changes %Changes{
    summary: %{
      applications: %{
        new: [
          %Foundation.Yaml.Application{
            name: "myphoenixapp",
            language: "gleam",
            replicas: 5,
            deploy_rollback_timeout_ms: 700_000,
            deploy_schedule_interval_ms: 8000,
            replica_ports: [
              %Foundation.Yaml.Ports{key: "PORT", base: 4000},
              %Foundation.Yaml.Ports{key: "MYPHOENIX_APP_PORT_TEST_1", base: 9000}
            ],
            env: ["SECRET_KEY_BASE=secret", "PHX_SERVER=true"],
            monitoring: [
              process: %Foundation.Yaml.Monitoring{
                enable_restart: true,
                warning_threshold_percent: 75,
                restart_threshold_percent: 90
              },
              port: %Foundation.Yaml.Monitoring{
                enable_restart: true,
                warning_threshold_percent: 75,
                restart_threshold_percent: 90
              }
            ]
          },
          %Foundation.Yaml.Application{
            name: "another_myumbrella",
            language: "elixir",
            replicas: 1,
            deploy_rollback_timeout_ms: 600_000,
            deploy_schedule_interval_ms: 5000,
            replica_ports: [%Foundation.Yaml.Ports{key: "PORT", base: 6040}],
            env: [
              "SECRET_KEY_BASE=secret",
              "PHX_SERVER=true",
              "DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod"
            ],
            monitoring: []
          }
        ],
        old: [
          %{
            env: [
              "SECRET_KEY_BASE=secret",
              "PHX_SERVER=true",
              "DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod"
            ],
            name: "myphoenixapp",
            monitoring: [
              atom: %{
                enable_restart: true,
                warning_threshold_percent: 75,
                restart_threshold_percent: 90
              },
              process: %{
                enable_restart: true,
                warning_threshold_percent: 75,
                restart_threshold_percent: 90
              },
              port: %{
                enable_restart: true,
                warning_threshold_percent: 75,
                restart_threshold_percent: 90
              }
            ],
            replicas: 2,
            language: "elixir",
            deploy_rollback_timeout_ms: 600_000,
            deploy_schedule_interval_ms: 5000,
            replica_ports: [
              %{base: 4000, key: "PORT"},
              %{base: 9000, key: "MYPHOENIX_APP_PORT_TEST_1"},
              %{base: 8000, key: "MYPHOENIX_APP_PORT_TEST_2"}
            ]
          },
          %{
            env: [
              "SECRET_KEY_BASE=secret",
              "PHX_SERVER=true",
              "DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod"
            ],
            name: "myumbrella",
            monitoring: [
              atom: %{
                enable_restart: false,
                warning_threshold_percent: 75,
                restart_threshold_percent: 90
              }
            ],
            replicas: 1,
            language: "elixir",
            deploy_rollback_timeout_ms: 600_000,
            deploy_schedule_interval_ms: 5000,
            replica_ports: [%{base: 4040, key: "PORT"}]
          }
        ],
        details: %{
          "another_myumbrella" => %{
            status: :added,
            config: %Foundation.Yaml.Application{
              name: "another_myumbrella",
              language: "elixir",
              replicas: 1,
              deploy_rollback_timeout_ms: 600_000,
              deploy_schedule_interval_ms: 5000,
              replica_ports: [%Foundation.Yaml.Ports{key: "PORT", base: 6040}],
              env: [
                "SECRET_KEY_BASE=secret",
                "PHX_SERVER=true",
                "DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod"
              ],
              monitoring: []
            }
          },
          "myphoenixapp" => %{
            status: :modified,
            changes: %{
              env: %{
                new: ["PHX_SERVER=true", "SECRET_KEY_BASE=secret"],
                old: [
                  "DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod",
                  "PHX_SERVER=true",
                  "SECRET_KEY_BASE=secret"
                ],
                apply_strategy: :next_deploy
              },
              monitoring: %{
                new: [
                  process: %Foundation.Yaml.Monitoring{
                    enable_restart: true,
                    warning_threshold_percent: 75,
                    restart_threshold_percent: 90
                  },
                  port: %Foundation.Yaml.Monitoring{
                    enable_restart: true,
                    warning_threshold_percent: 75,
                    restart_threshold_percent: 90
                  }
                ],
                old: [
                  atom: %{
                    enable_restart: true,
                    warning_threshold_percent: 75,
                    restart_threshold_percent: 90
                  },
                  process: %{
                    enable_restart: true,
                    warning_threshold_percent: 75,
                    restart_threshold_percent: 90
                  },
                  port: %{
                    enable_restart: true,
                    warning_threshold_percent: 75,
                    restart_threshold_percent: 90
                  }
                ],
                apply_strategy: :immediate
              },
              replicas: %{new: 5, old: 2, apply_strategy: :immediate},
              language: %{new: "gleam", old: "elixir", apply_strategy: :next_deploy},
              deploy_rollback_timeout_ms: %{
                new: 700_000,
                old: 600_000,
                apply_strategy: :immediate
              },
              deploy_schedule_interval_ms: %{new: 8000, old: 5000, apply_strategy: :immediate},
              replica_ports: %{
                new: [
                  %Foundation.Yaml.Ports{key: "PORT", base: 4000},
                  %Foundation.Yaml.Ports{
                    key: "MYPHOENIX_APP_PORT_TEST_1",
                    base: 9000
                  }
                ],
                old: [
                  %{base: 4000, key: "PORT"},
                  %{base: 9000, key: "MYPHOENIX_APP_PORT_TEST_1"},
                  %{base: 8000, key: "MYPHOENIX_APP_PORT_TEST_2"}
                ],
                apply_strategy: :full_deploy
              }
            }
          },
          "myumbrella" => %{
            status: :removed,
            config: %{
              env: [
                "SECRET_KEY_BASE=secret",
                "PHX_SERVER=true",
                "DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod"
              ],
              name: "myumbrella",
              monitoring: [
                atom: %{
                  enable_restart: false,
                  warning_threshold_percent: 75,
                  restart_threshold_percent: 90
                }
              ],
              replicas: 1,
              language: "elixir",
              deploy_rollback_timeout_ms: 600_000,
              deploy_schedule_interval_ms: 5000,
              replica_ports: [%{base: 4040, key: "PORT"}]
            }
          }
        }
      },
      monitoring: %{
        new: [
          process: %Foundation.Yaml.Monitoring{
            enable_restart: true,
            warning_threshold_percent: 75,
            restart_threshold_percent: 95
          }
        ],
        old: [
          memory: %{
            enable_restart: true,
            warning_threshold_percent: 75,
            restart_threshold_percent: 95
          }
        ],
        apply_strategy: :immediate
      },
      logs_retention_time_ms: %{new: 45_600_000, old: 3_600_000, apply_strategy: :immediate},
      metrics_retention_time_ms: %{new: 45_600_000, old: 3_600_000, apply_strategy: :immediate}
    },
    timestamp: ~U[2025-11-14 23:41:07.000464Z],
    changes_count: 4
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

          # Set pending config
          :sys.replace_state(pid, fn state ->
            %{
              state
              | pending_config: %Upgradable{},
                pending_changes: @summary_with_all_possible_changes
            }
          end)

          assert :ok = Watcher.apply_changes(pid)

          # Verify broadcast received
          assert_receive {:watcher_config_apply, ^node, @summary_with_all_possible_changes}, 1000
        end)

      assert log =~ "ConfigWatcher: Removing application: myumbrella"
    end
  end
end
