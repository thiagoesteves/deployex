defmodule Foundation.ConfigProvider.Secrets.Env do
  @moduledoc """
  Adapter implementation for retrieving secrets from Environment
  """
  @behaviour Foundation.ConfigProvider.Secrets.Adapter

  @required_secrets [
    "DEPLOYEX_ADMIN_HASHED_PASSWORD",
    "DEPLOYEX_SECRET_KEY_BASE",
    "DEPLOYEX_ERLANG_COOKIE"
  ]

  # Fetched only when set, so a deployment without the feature does not have to
  # define them.
  @optional_secrets [
    "DEPLOYEX_OAUTH_CLIENT_SECRET"
  ]

  @doc """
  secrets/3.

  Args:
    - The current config
    - secret_path_id: Path to the secret content, e. g. deployex-{app}-prod-secrets
    - opts is just the return value of init/1.
  """
  @impl true
  def secrets(_config, _secret_path, _opts) do
    required =
      Enum.reduce(@required_secrets, %{}, fn secret, acc ->
        Map.put(acc, secret, System.fetch_env!(secret))
      end)

    Enum.reduce(@optional_secrets, required, fn secret, acc ->
      case System.get_env(secret) do
        nil -> acc
        value -> Map.put(acc, secret, value)
      end
    end)
  end
end
