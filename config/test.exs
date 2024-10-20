import Config

monitored_app_name = "testapp"

config :deployex,
  env: "local",
  base_path: "/tmp/deployex/test/varlib",
  monitored_app_name: monitored_app_name,
  monitored_app_log_path: "/tmp/#{monitored_app_name}",
  monitored_app_start_port: 4444

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :deployex, DeployexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hQ1CDXnnsqNi2+sEYF2SSOkj+SrzzqtbwtfjjHYgNDdH97obAtrDPjtN3HyAy6ns",
  server: false

# In test we don't send emails.
config :deployex, Deployex.Mailer, adapter: Swoosh.Adapters.Test

# Config Mock for Monitor
config :deployex, Deployex.Monitor, adapter: Deployex.MonitorMock

# Config Mock for Monitor
config :deployex, Deployex.Status, adapter: Deployex.StatusMock

# Config Mock for Release
config :deployex, Deployex.Release,
  adapter: Deployex.ReleaseMock,
  bucket: "/tmp/#{monitored_app_name}"

# Config Mock for Upgrade
config :deployex, Deployex.Upgrade, adapter: Deployex.UpgradeMock

# Config Mock for Operational System
config :deployex, Deployex.OpSys, adapter: Deployex.OpSysMock

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
