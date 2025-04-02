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

config :deployex,
  generators: [timestamp_type: :utc_datetime],
  booted_at: System.monotonic_time(),
  bin_dir: "/opt/deployex/bin",
  bin_path: "/opt/deployex/bin/deployex",
  log_path: "/var/log/deployex",
  replicas: 3,
  monitored_app_start_port: 4000

# NOTE: The default username/pass is admin/admin and in order to generate
#       the hashed password, it is required to use:
#       > Bcrypt.hash_pwd_salt("deployex")
config :deployex, Deployex.Accounts,
  admin_hashed_password:
    System.get_env(
      "DEPLOYEX_ADMIN_HASHED_PASSWORD",
      "$2b$12$vNAn.RJezPdQF7Dcy4c9Q.p34hdeNnkIaGTk80xdc/Rk18vWjUOC."
    )

config :deployex, Deployex.Deployment,
  timeout_rollback: :timer.minutes(10),
  schedule_interval: :timer.seconds(5),
  delay_between_deploys_ms: :timer.seconds(1)

# Configures the endpoint
config :deployex, DeployexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DeployexWeb.ErrorHTML, json: DeployexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Deployex.PubSub,
  live_view: [signing_salt: "t2YabqhV"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :deployex, Deployex.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  deployex: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  deployex: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configures Elixir's Logger
config :logger, :console,
  format: "$time [$level] $metadata $message\n",
  metadata: [:instance, :module, :function, :pid]

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
  http_client: Deployex.Aws.ExAwsHttpClient

config :deployex, Deployex.Monitor, adapter: Deployex.Monitor.Application

config :deployex, Deployex.Status, adapter: Deployex.Status.Application

config :deployex, Deployex.Upgrade, adapter: Deployex.Upgrade.Application

config :deployex, Deployex.OpSys, adapter: Deployex.OpSys.Local

config :deployex, Deployex.Catalog, adapter: Deployex.Catalog.Local

config :deployex, Deployex.Rpc, adapter: Deployex.Rpc.Local

# Configure Logs retention time for 60 minutes
config :deployex, Deployex.Logs,
  adapter: Deployex.Logs.Server,
  data_retention_period: :timer.minutes(60)

# Configure Observer Web retention time for 60 minutes
config :observer_web, ObserverWeb.Telemetry,
  data_retention_period: :timer.minutes(60),
  mode: :observer

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
