defmodule Foundation.ConfigProvider.Secrets.Env do
  @moduledoc """
  Adapter implementation for retrieving secrets from Environment
  """
  @behaviour Foundation.ConfigProvider.Secrets.Adapter

  require Logger

  @secrets [
    "DEPLOYEX_ADMIN_HASHED_PASSWORD",
    "DEPLOYEX_SECRET_KEY_BASE",
    "DEPLOYEX_ERLANG_COOKIE"
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
    Enum.reduce(@secrets, %{}, fn secret, acc ->
      Map.put(acc, secret, System.fetch_env!(secret))
    end)
  end
end
