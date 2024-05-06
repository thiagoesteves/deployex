import Config

config :deployex,
  base_path: "/var/lib/deployex"

# Do not print debug messages in production
config :logger, level: :info
