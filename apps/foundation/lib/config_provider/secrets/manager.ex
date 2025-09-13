defmodule Foundation.ConfigProvider.Secrets.Manager do
  @moduledoc """
  https://hexdocs.pm/elixir/main/Config.Provider.html

  Fetch secrets from various secret management systems (AWS Secrets Manager,
  HashiCorp Vault, GCP Secret Manager), then load those secrets into configs.

  Similar examples:
    - https://github.com/Adzz/gcp_secret_provider/blob/master/lib/gcp_secret_provider.ex
    - https://github.com/sevenmind/vault_config_provider
  """
  @behaviour Config.Provider

  require Logger

  @impl Config.Provider
  def init(_path), do: []

  @doc """
  load/2.

  Args:
    - config is the current config
    - opts is just the return value of init/1.

  Calls out to the configured secrets adapter, parses the response, sets configs to parsed response.
  """
  @impl Config.Provider
  def load(config, opts) do
    Logger.info("Running Config Provider for Secrets")
    env = Keyword.get(config, :foundation) |> Keyword.get(:env)

    # Get all secrets manager configuration
    secrets_manager_config =
      Keyword.get(config, :foundation)
      |> Keyword.get(Foundation.ConfigProvider.Secrets.Manager, [])

    secrets_adapter = Keyword.get(secrets_manager_config, :adapter)
    secrets_path = Keyword.get(secrets_manager_config, :path)

    # Pass opts directly to adapter (opts is always [] from init/1)
    adapter_opts = opts

    if env == "local" do
      Logger.info("  - No secrets retrieved, local environment")
      config
    else
      Logger.info("  - Trying to retrieve secrets: #{secrets_adapter} - #{secrets_path}")

      # Add secrets manager config to the config for adapters to access
      adapter_config =
        Keyword.put(config, Foundation.ConfigProvider.Secrets.Manager, secrets_manager_config)

      secrets = secrets_adapter.secrets(adapter_config, secrets_path, adapter_opts)

      admin_hashed_password =
        keyword(:admin_hashed_password, secrets["DEPLOYEX_ADMIN_HASHED_PASSWORD"])

      secret_key_base = keyword(:secret_key_base, secrets["DEPLOYEX_SECRET_KEY_BASE"])
      erlang_cookie = secrets["DEPLOYEX_ERLANG_COOKIE"] |> String.to_atom()

      # Config Erlang Cookie if the node exist
      node = Node.self()

      if node != :nonode@nohost do
        Node.set_cookie(node, erlang_cookie)
      end

      Config.Reader.merge(
        config,
        foundation: [
          {Foundation.Accounts, admin_hashed_password}
        ],
        deployex_web: [
          {DeployexWeb.Endpoint, secret_key_base}
        ]
      )
    end
  end

  defp keyword(key_name, value) do
    Keyword.new([{key_name, value}])
  end


end
