defmodule Sentinel.Fixture.Watcher do
  @moduledoc false
  alias Sentinel.Config.Changes

  def build_pending_changes do
    %Changes{
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
              },
              apply_strategies: [:immediate]
            },
            "myphoenixapp" => %{
              status: :modified,
              changes: %{
                env: %{
                  new: [],
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
              },
              apply_strategies: [:immediate, :full_deploy, :next_deploy]
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
              },
              apply_strategies: [:immediate]
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
  end
end
