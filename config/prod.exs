import Config

config :deployex,
  base_path: "/var/lib/deployex"

config :deployex, Deployex.Storage, adapter: Deployex.Storage.S3

# Do not print debug messages in production
config :logger, level: :info
