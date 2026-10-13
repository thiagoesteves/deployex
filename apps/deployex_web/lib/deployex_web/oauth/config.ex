defmodule DeployexWeb.OAuth.Config do
  @moduledoc """
  Reads OAuth configuration for deployex_web.

  Non-secret fields (provider, client_id, allowlist) come from the app
  environment, populated from the YAML `auth` section. The `client_secret` is
  fetched separately through the secrets provider.

  OAuth is considered configured only when the `client_id`, the `client_secret`
  and the `redirect_uri` are all set, so the provider button stays off until
  then. Defaults are fail-closed: no config means an empty (deny-all) allowlist.
  """

  require Logger

  @default_provider DeployexWeb.OAuth.Provider.GitHub
  @empty_allowlist %{emails: [], domains: []}

  # Each required field, with the name the operator sets it by
  @required [
    client_id: "auth.client_id",
    client_secret: "DEPLOYEX_OAUTH_CLIENT_SECRET",
    redirect_uri: "auth.redirect_uri"
  ]

  @spec configured?() :: boolean()
  def configured?, do: missing() == []

  @doc """
  Logs a warning when only part of the config is set, since OAuth then stays off.
  """
  @spec warn_if_incomplete() :: :ok
  def warn_if_incomplete do
    missing = missing()
    partly_set? = length(missing) < length(@required) or allowlist() != @empty_allowlist

    if missing != [] and partly_set? do
      Logger.warning("OAuth sign-in is off because the config has no #{Enum.join(missing, ", ")}")
    end

    :ok
  end

  @spec provider_module() :: module()
  def provider_module, do: Keyword.get(config(), :provider, @default_provider)

  @spec client_id() :: String.t() | nil
  def client_id, do: Keyword.get(config(), :client_id)

  @spec client_secret() :: String.t() | nil
  def client_secret, do: Keyword.get(config(), :client_secret)

  @spec redirect_uri() :: String.t() | nil
  def redirect_uri, do: Keyword.get(config(), :redirect_uri)

  @spec allowlist() :: map()
  def allowlist, do: Keyword.get(config(), :allowlist, @empty_allowlist)

  defp missing do
    for {key, name} <- @required, not present?(Keyword.get(config(), key)), do: name
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp config, do: Application.get_env(:deployex_web, DeployexWeb.OAuth, [])
end
