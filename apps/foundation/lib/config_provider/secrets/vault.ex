defmodule Foundation.ConfigProvider.Secrets.Vault do
  @moduledoc """
  HashiCorp Vault adapter using Vaultx client library.

  This adapter integrates with HashiCorp Vault using the Vaultx library
  to provide secure secret management for DeployEx applications.

  ## Configuration

  All configuration values must come from the config system, not environment variables.
  Environment variables are only used in runtime.exs and dev.exs to inject values into config.

  ## YAML Configuration Example:

      secrets_adapter: "vault"
      secrets_path: "deployex/prod/secrets"
      vault_mount_path: "secret"  # optional, defaults to "secret"
      vault_url: "https://vault.example.com:8200"

  ## Runtime Configuration

  In config/runtime.exs (for production):
      config :foundation, Foundation.ConfigProvider.Secrets.Manager,
        vault_url: System.get_env("VAULTX_URL"),
        vault_token: System.get_env("VAULTX_TOKEN"),
        vault_mount_path: System.get_env("VAULTX_MOUNT_PATH")

  In config/dev.exs (for development):
      config :foundation, Foundation.ConfigProvider.Secrets.Manager,
        vault_url: System.get_env("VAULTX_URL"),
        vault_token: System.get_env("VAULTX_TOKEN"),
        vault_mount_path: System.get_env("VAULTX_MOUNT_PATH")

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

    with :ok <- configure_vaultx(config, opts) do
      vault_opts = build_vault_options(config, opts)

      case fetch_vault_secrets(secret_path, vault_opts) do
        {:ok, secrets} ->
          Logger.info("Successfully retrieved #{map_size(secrets)} secrets from Vault")
          secrets

        {:error, reason} ->
          Logger.error("Failed to retrieve secrets from Vault: #{inspect(reason)}")
          raise "Vault secret retrieval failed: #{inspect(reason)}"
      end
    else
      {:error, reason} ->
        Logger.error("Failed to configure Vault: #{inspect(reason)}")
        raise "Vault configuration failed: #{inspect(reason)}"
    end
  end

  defp ensure_vaultx_available! do
    if not Code.ensure_loaded?(Vaultx.Secrets.KV.V2) do
      raise """
      Vaultx dependency is required for Vault secrets adapter.

      Add to your mix.exs:
      {:vaultx, "~> 0.7"}

      Then run: mix deps.get
      """
    end
  end

  defp build_vault_options(config, opts) do
    mount_path = get_mount_path(config, opts)

    [
      mount_path: mount_path,
      # Disable cache, let DeployEx manage caching
      cache: false
    ]
  end

  defp get_mount_path(config, _opts) do
    Keyword.get(config, Foundation.ConfigProvider.Secrets.Manager)
    |> Keyword.get(:vault_mount_path) ||
      "secret"
  end

  defp fetch_vault_secrets(secret_path, vault_opts) do
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
  end

  defp configure_vaultx(config, _opts) do
    vault_url =
      Keyword.get(config, Foundation.ConfigProvider.Secrets.Manager) |> Keyword.get(:vault_url)

    vault_token =
      Keyword.get(config, Foundation.ConfigProvider.Secrets.Manager) |> Keyword.get(:vault_token)

    case {vault_url, vault_token} do
      {nil, _any} ->
        {:error, "vault_url is required in configuration"}

      {"", _any} ->
        {:error, "vault_url is required in configuration"}

      {_any, nil} ->
        {:error, "vault_token is required in configuration"}

      {_any, ""} ->
        {:error, "vault_token is required in configuration"}

      {url, token} ->
        vaultx_config = %{
          url: url,
          token: token
        }

        Application.put_env(:vaultx, :config, vaultx_config)
        :ok
    end
  end
end
