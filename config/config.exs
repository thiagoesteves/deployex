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

monitored_app_name = System.get_env("DEPLOYEX_MONITORED_APP_NAME", "myphoenixapp")

config :deployex,
  generators: [timestamp_type: :utc_datetime],
  env: "local",
  log_file: "/var/log/deployex.log",
  base_path: "/tmp/deployex/varlib",
  replicas: 3,
  monitored_app_name: monitored_app_name,
  monitored_app_log_path: "/tmp/#{monitored_app_name}",
  monitored_app_phx_start_port: 4000

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
  ]

config :deployex, Deployex.Storage, adapter: Deployex.Storage.Local

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
