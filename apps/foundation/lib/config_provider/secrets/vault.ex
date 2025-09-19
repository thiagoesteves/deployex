defmodule Foundation.ConfigProvider.Secrets.Vault do
  @moduledoc """
  Adapter implementation 
  HashiCorp Vault adapter using Vaultx client library for retrieving secrets from AWS secret manager

  This adapter integrates with HashiCorp Vault using the Vaultx library
  to provide secure secret management for DeployEx applications.
  """

  @behaviour Foundation.ConfigProvider.Secrets.Adapter

  alias Vaultx.Secrets.KV

  @doc """
  secrets/3.

  Args:
    - The current config
    - secret_path_id: Path to the secret content, e. g. deployex-{app}-prod-secrets
    - opts is just the return value of init/1.
  """
  @impl Foundation.ConfigProvider.Secrets.Adapter
  def secrets(config, secret_path, _opts) do
    {:ok, _} = Application.ensure_all_started(:vaultx)

    mount_path =
      config
      |> Keyword.get(:vaultx)
      |> Keyword.get(:mount_path) || "secret"

    case KV.read(secret_path, mount_path: mount_path, cache: false) do
      {:ok, %{data: secrets}} when is_map(secrets) ->
        secrets

      {:error, reason} ->
        raise "Vault secret retrieval failed: #{inspect(reason)}"
    end
  end
end
