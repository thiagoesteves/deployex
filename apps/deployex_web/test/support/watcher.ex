defmodule DeployexWeb.Fixture.Watcher do
  @moduledoc false
  def build_pending_changes do
    %Sentinel.Config.Changes{
      summary: %{
        applications: %{
          new: ["myumbrella", "another_myumbrella"],
          old: ["myphoenixapp", "myumbrella"],
          details: %{
            "another_myumbrella" => %{
              status: :added,
              config: %Foundation.Yaml.Application{
                name: "another_myumbrella",
                language: "elixir",
                replicas: 1,
                replica_ports: [%Foundation.Yaml.Ports{key: "PORT", base: 4040}],
                env: [
                  "SECRET_KEY_BASE=secret",
                  "PHX_SERVER=true",
                  "DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod"
                ],
                monitoring: [
                  atom: %Foundation.Yaml.Monitoring{
                    enable_restart: false,
                    warning_threshold_percent: 75,
                    restart_threshold_percent: 80
                  }
                ]
              }
            },
            "myphoenixapp" => %{
              status: :removed,
              config: %{
                env: [
                  "SECRET_KEY_BASE=secret",
                  "PHX_SERVER=true"
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
                replica_ports: [
                  %{base: 4000, key: "PORT"},
                  %{base: 3000, key: "MYPHOENIX_APP_PORT_TEST_1"},
                  %{base: 8000, key: "MYPHOENIX_APP_PORT_TEST_2"}
                ]
              }
            },
            "myumbrella" => %{
              status: :modified,
              changes: %{
                replicas: %{new: 2, old: 3},
                language: %{new: "gleam", old: "elixir"},
                env: %{
                  new: [],
                  old: [
                    "SECRET_KEY_BASE=secret",
                    "PHX_SERVER=true"
                  ]
                },
                replica_ports: %{
                  new: [
                    %{base: 4000, key: "PORT"},
                    %{base: 3000, key: "MYPHOENIX_APP_PORT_TEST_1"},
                    %{base: 8000, key: "MYPHOENIX_APP_PORT_TEST_2"}
                  ],
                  old: []
                },
                monitoring: %{
                  new: [
                    atom: %Foundation.Yaml.Monitoring{
                      enable_restart: false,
                      warning_threshold_percent: 75,
                      restart_threshold_percent: 80
                    }
                  ],
                  old: [
                    atom: %{
                      enable_restart: false,
                      warning_threshold_percent: 75,
                      restart_threshold_percent: 90
                    }
                  ]
                }
              }
            }
          }
        },
        monitoring: %{
          new: [
            atom: %Foundation.Yaml.Monitoring{
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
          ]
        },
        logs_retention_time_ms: %{new: 3_700_000, old: 3_600_000},
        deploy_rollback_timeout_ms: %{new: 700_000, old: 600_000},
        deploy_schedule_interval_ms: %{new: 10_000, old: 5_000},
        metrics_retention_time_ms: %{new: 10_000, old: 5_000}
      },
      timestamp: DateTime.utc_now(),
      changes_count: 5
    }
  end
end
