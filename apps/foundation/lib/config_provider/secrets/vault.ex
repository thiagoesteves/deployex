defmodule Foundation.ConfigProvider.Secrets.Vault do
  @moduledoc """
  HashiCorp Vault adapter using Vaultx client library.

  This adapter integrates with HashiCorp Vault using the Vaultx library
  to provide secure secret management for DeployEx applications.

  ## Configuration

  Environment variables:
  - VAULTX_URL: Vault server URL (required)
  - VAULTX_TOKEN: Vault authentication token (required)
  - VAULTX_NAMESPACE: Vault namespace (optional, Enterprise only)
  - VAULTX_MOUNT_PATH: KV mount path (optional, default: "secret")

  ## YAML Configuration Example:

      secrets_adapter: "vault"
      secrets_path: "deployex/prod/config"
      vault_mount_path: "secret"  # optional

  ## Required Dependencies

  Add to your mix.exs:
      {:vaultx, "~> 0.7"}

  ## Usage Examples

      # Basic usage
      secrets = Foundation.ConfigProvider.Secrets.Vault.secrets(
        [],
        "deployex/prod/secrets",
        [vault_mount_path: "secret"]
      )

      # With custom mount path
      secrets = Foundation.ConfigProvider.Secrets.Vault.secrets(
        [],
        "myapp/config",
        [vault_mount_path: "custom-kv"]
      )
  """

  @behaviour Foundation.ConfigProvider.Secrets.Adapter

  require Logger

  @impl Foundation.ConfigProvider.Secrets.Adapter
  def secrets(config, secret_path, opts) do
    ensure_vaultx_available!()

    Logger.info("Retrieving secrets from Vault: #{secret_path}")

    vault_opts = build_vault_options(config, opts)

    case fetch_vault_secrets(secret_path, vault_opts) do
      {:ok, secrets} ->
        Logger.info("Successfully retrieved #{map_size(secrets)} secrets from Vault")
        secrets

      {:error, reason} ->
        Logger.error("Failed to retrieve secrets from Vault: #{inspect(reason)}")
        raise "Vault secret retrieval failed: #{inspect(reason)}"
    end
  end

  defp ensure_vaultx_available! do
    unless Code.ensure_loaded?(Vaultx.Secrets.KV.V2) do
      raise """
      Vaultx dependency is required for Vault secrets adapter.

      Add to your mix.exs:
      {:vaultx, "~> 0.7"}

      Then run: mix deps.get
      """
    end
  end

  defp build_vault_options(_config, opts) do
    mount_path = get_mount_path(opts)

    [
      mount_path: mount_path,
      # Disable cache, let DeployEx manage caching
      cache: false
    ]
  end

  defp get_mount_path(opts) do
    Keyword.get(opts, :vault_mount_path) ||
      System.get_env("VAULTX_MOUNT_PATH") ||
      "secret"
  end

  defp fetch_vault_secrets(secret_path, vault_opts) do
    case validate_vaultx_config() do
      :ok ->
        case Vaultx.Secrets.KV.V2.read(secret_path, vault_opts) do
          {:ok, %{data: data}} when is_map(data) ->
            {:ok, data}

          {:ok, response} ->
            Logger.warning("Unexpected Vault response format: #{inspect(response)}")
            {:error, :invalid_response_format}

          {:error, %Vaultx.Base.Error{type: :not_found}} ->
            {:error, :secret_not_found}

          {:error, %Vaultx.Base.Error{} = error} ->
            {:error, error}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_vaultx_config do
    try do
      url = System.get_env("VAULTX_URL")
      token = System.get_env("VAULTX_TOKEN")

      cond do
        is_nil(url) or url == "" ->
          {:error, "VAULTX_URL environment variable is required"}

        is_nil(token) or token == "" ->
          {:error, "VAULTX_TOKEN environment variable is required"}

        true ->
          :ok
      end
    rescue
      error ->
        {:error, "Vaultx configuration error: #{inspect(error)}"}
    end
  end
end
