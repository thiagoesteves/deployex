import Config

base_test_path = "/tmp/deployex-test"

config :foundation,
  env: "local",
  install_path: "#{base_test_path}/opt/deployex",
  log_path: "#{base_test_path}/var/log/deployex",
  var_path: "#{base_test_path}/var/lib/deployex",
  monitored_app_log_path: "#{base_test_path}/var/log/monitored-apps",
  monitoring: [
    memory: %{
      enable_restart: true,
      warning_threshold_percent: 10,
      restart_threshold_percent: 20
    }
  ],
  applications: [
    %{
      name: "myelixir",
      replicas: 3,
      language: "elixir",
      deploy_rollback_timeout_ms: 600_000,
      deploy_schedule_interval_ms: 5000,
      replica_ports: [%{key: "PORT", base: 4444}],
      env: ["SECRET=value", "PHX_SERVER=true"],
      monitoring: [
        port: %{
          enable_restart: true,
          warning_threshold_percent: 10,
          restart_threshold_percent: 20
        },
        process: %{
          enable_restart: true,
          warning_threshold_percent: 10,
          restart_threshold_percent: 20
        },
        atom: %{
          enable_restart: true,
          warning_threshold_percent: 10,
          restart_threshold_percent: 20
        }
      ]
    },
    %{
      name: "myerlang",
      replicas: 3,
      language: "erlang",
      deploy_rollback_timeout_ms: 600_000,
      deploy_schedule_interval_ms: 5000,
      replica_ports: [%{key: "PORT", base: 5555}],
      env: ["SECRET=value", "PHX_SERVER=true"],
      monitoring: [
        port: %{
          enable_restart: false,
          warning_threshold_percent: 10,
          restart_threshold_percent: 20
        },
        process: %{
          enable_restart: true,
          warning_threshold_percent: 10,
          restart_threshold_percent: 20
        },
        atom: %{
          enable_restart: true,
          warning_threshold_percent: 10,
          restart_threshold_percent: 20
        }
      ]
    },
    %{
      name: "mygleam",
      replicas: 3,
      language: "gleam",
      deploy_rollback_timeout_ms: 600_000,
      deploy_schedule_interval_ms: 5000,
      replica_ports: [%{key: "PORT", base: 6666}],
      env: ["SECRET=value", "PHX_SERVER=true"],
      monitoring: []
    }
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :deployex_web, DeployexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hQ1CDXnnsqNi2+sEYF2SSOkj+SrzzqtbwtfjjHYgNDdH97obAtrDPjtN3HyAy6ns",
  server: false

# In test we don't send emails
config :deployex_web, DeployexWeb.Mailer, adapter: Swoosh.Adapters.Test

# Config Mocks for Deployer
config :deployer, Deployer.Monitor, adapter: Deployer.MonitorMock

config :deployer, Deployer.Release,
  adapter: Deployer.ReleaseMock,
  bucket: "/tmp/deployex-test/bucket"

config :deployer, Deployer.Status, adapter: Deployer.StatusMock

config :deployer, Deployer.Upgrade, adapter: Deployer.UpgradeMock

# Config Mocks for Host
config :host, Host.Commander, adapter: Host.CommanderMock

# Config Mocks for Foundation
config :foundation, Foundation.Rpc, adapter: Foundation.RpcMock

# Config Mock for Sentinel
config :sentinel, Sentinel.Logs, adapter: Sentinel.LogsMock

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
