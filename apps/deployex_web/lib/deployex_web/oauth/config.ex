defmodule DeployexWeb.OAuth.Config do
  @moduledoc """
  Reads OAuth configuration for deployex_web.

  Non-secret fields (provider, client_id, allowlist) come from the app
  environment, populated from the YAML `auth` section. The `client_secret` is
  fetched separately through the secrets provider.

  OAuth is considered configured only when a `client_id` is present, so the
  provider button and routes stay off until it is set. Defaults are
  fail-closed: no config means an empty (deny-all) allowlist.
  """

  @default_provider DeployexWeb.OAuth.Provider.GitHub
  @empty_allowlist %{emails: [], domains: []}

  @spec configured?() :: boolean()
  def configured?, do: is_binary(client_id())

  @spec provider_module() :: module()
  def provider_module, do: Keyword.get(config(), :provider, @default_provider)

  @spec client_id() :: String.t() | nil
  def client_id, do: Keyword.get(config(), :client_id)

  @spec allowlist() :: map()
  def allowlist, do: Keyword.get(config(), :allowlist, @empty_allowlist)

  defp config, do: Application.get_env(:deployex_web, DeployexWeb.OAuth, [])
end
