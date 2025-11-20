# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :foundation,
  generators: [timestamp_type: :utc_datetime],
  booted_at: System.monotonic_time(),
  # DeployEx Installation path in the host machine
  install_path: "/opt/deployex",
  log_path: "/var/log/deployex",
  # DeployEx managed data like monitored apps, storage, etc
  var_path: "/var/lib/deployex",
  monitored_app_log_path: "/var/log/monitored-apps",
  monitoring: [],
  applications: [],
  healthcheck_logging: false,
  logs_retention_time_ms: :timer.hours(1),
  config_checksum: nil

# NOTE: The default username/pass is admin/deployex and in order to generate
#       the hashed password, it is required to use:
#       > Bcrypt.hash_pwd_salt("deployex")
config :foundation, Foundation.Accounts,
  admin_hashed_password:
    System.get_env(
      "DEPLOYEX_ADMIN_HASHED_PASSWORD",
      "$2b$12$vNAn.RJezPdQF7Dcy4c9Q.p34hdeNnkIaGTk80xdc/Rk18vWjUOC."
    )

# Configures the endpoint
config :deployex_web, DeployexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DeployexWeb.ErrorHTML, json: DeployexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DeployexWeb.PubSub,
  live_view: [signing_salt: "NiuvxePg"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :deployex_web, DeployexWeb.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  deployex_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/deployex_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  deployex_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/deployex_web", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time [$level] $metadata $message\n",
  metadata: [:instance, :module, :function, :pid]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# AWS Configuration
config :ex_aws,
  access_key_id: [
    {:system, "AWS_ACCESS_KEY_ID"},
    {:awscli, :system, 30},
    :instance_role
  ],
  secret_access_key: [
    {:system, "AWS_SECRET_ACCESS_KEY"},
    {:awscli, :system, 30},
    :instance_role
  ],
  http_client: Deployer.Aws.ExAwsHttpClient

# Foundation Adapters
config :foundation, Foundation.Rpc, adapter: Foundation.Rpc.Local

config :foundation, Foundation.Catalog, adapter: Foundation.Catalog.Local

# Host Adapters
config :host, Host.Commander, adapter: Host.Commander.Local

# Deployer Adapters
config :deployer, Deployer.Monitor, adapter: Deployer.Monitor.Application

config :deployer, Deployer.Status, adapter: Deployer.Status.Application

config :deployer, Deployer.Upgrade, adapter: Deployer.Upgrade.Application

# Default GCP credentials are empty
config :goth, file_credentials: nil

# Configure Logs retention time
config :sentinel, Sentinel.Logs, adapter: Sentinel.Logs.Server

# Configure Observer Web retention time
config :observer_web,
  data_retention_period: :timer.minutes(60),
  mode: :observer

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# File used for configuration overrides and individual secrets.
# Set config on this file according to the desired MIX_ENV.
override_file = "#{config_env()}.override.exs"

if File.exists?("config/#{override_file}") or File.exists?("../../config/#{override_file}") do
  import_config override_file
end
