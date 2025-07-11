import Config

config :foundation,
  env: "local",
  base_path: "/tmp/deployex/test/varlib",
  bin_dir: "/tmp/deployex/test/opt",
  bin_path: "/tmp/deployex/test/opt/deployex",
  monitored_app_log_path: "/tmp/deployex/test/varlog",
  applications: [
    %{
      name: "myelixir",
      replicas: 3,
      language: "elixir",
      initial_port: 4444,
      env: ["SECRET=value", "PHX_SERVER=true"]
    },
    %{
      name: "myerlang",
      replicas: 3,
      language: "erlang",
      initial_port: 5555,
      env: ["SECRET=value", "PHX_SERVER=true"]
    },
    %{
      name: "mygleam",
      replicas: 3,
      language: "gleam",
      initial_port: 6666,
      env: ["SECRET=value", "PHX_SERVER=true"]
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
  bucket: "/tmp/deployex/test/bucket"

config :deployer, Deployer.Status, adapter: Deployer.StatusMock

config :deployer, Deployer.Upgrade, adapter: Deployer.UpgradeMock

# Config Mocks for Host
config :host, Host.Commander, adapter: Host.CommanderMock

# Config Mocks for Foundation
config :foundation, Foundation.Rpc, adapter: Foundation.RpcMock

# Config Mock for Sentinel
config :sentinel, Sentinel.Logs, adapter: Sentinel.LogsMock

config :sentinel, Sentinel.Watchdog,
  applications_config: [
    default: %{
      enable_restart: true,
      warning_threshold_percent: 10,
      restart_threshold_percent: 20
    },
    myelixir: [
      port: %{
        enable_restart: true,
        warning_threshold_percent: 10,
        restart_threshold_percent: 20
      },
      process: %{
        enable_restart: true,
        warning_threshold_percent: 10,
        restart_threshold_percent: 20
      }
    ]
  ],
  system_config: [
    memory: %{
      enable_restart: true,
      warning_threshold_percent: 10,
      restart_threshold_percent: 20
    }
  ]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
