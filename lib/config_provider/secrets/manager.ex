defmodule Deployex.ConfigProvider.Secrets.Manager do
  @moduledoc """
  https://hexdocs.pm/elixir/main/Config.Provider.html

  Fetch secrets from AWS Secrets Manager, then load those secrets into configs.

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

  Calls out to AWS Secrets Manager, parses the JSON response, sets configs to parsed response.
  """
  @impl Config.Provider
  def load(config, opts) do
    Logger.info("Running Config Provider for Secrets")
    env = Keyword.get(config, :deployex) |> Keyword.get(:env)

    secrets_adapter =
      Keyword.get(config, :deployex)
      |> Keyword.get(Deployex.ConfigProvider.Secrets.Manager)
      |> Keyword.get(:adapter)

    secrets_path =
      Keyword.get(config, :deployex)
      |> Keyword.get(Deployex.ConfigProvider.Secrets.Manager)
      |> Keyword.get(:path)

    if env == "local" do
      Logger.info("  - No secrets retrieved, local environment")
      config
    else
      Logger.info("  - Trying to retrieve secrets: #{secrets_adapter} - #{secrets_path}")

      secrets = secrets_adapter.secrets(config, secrets_path, opts)

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
        deployex: [
          {DeployexWeb.Endpoint, secret_key_base},
          {Deployex.Accounts, admin_hashed_password}
        ]
      )
    end
  end

  defp keyword(key_name, value) do
    Keyword.new([{key_name, value}])
  end
end
