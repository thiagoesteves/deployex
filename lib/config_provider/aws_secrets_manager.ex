defmodule Deployex.AwsSecretsManagerProvider do
  @moduledoc """
  https://hexdocs.pm/elixir/1.14.0-rc.1/Config.Provider.html

  Fetch secrets from AWS Secrets Manager, then load those secrets into configs.

  Similar examples:
    - https://github.com/Adzz/gcp_secret_provider/blob/master/lib/gcp_secret_provider.ex
    - https://github.com/sevenmind/vault_config_provider
  """
  @behaviour Config.Provider

  require Logger

  alias ExAws.Operation.JSON

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
    Logger.info("Running AWS config provider")
    env = Keyword.get(config, :deployex) |> Keyword.get(:env)

    if env == "local" do
      Logger.info("  - No secrets retrieved, local environment")
      config
    else
      {:ok, _} = Application.ensure_all_started(:hackney)
      {:ok, _} = Application.ensure_all_started(:ex_aws)

      Logger.info("  - Trying to retrieve secrets")

      region = System.fetch_env!("AWS_REGION")
      request_opts = Keyword.merge(opts, region: region)

      # NOTE: Cloud structures use "-" instead of "_".
      monitored_app_name =
        System.fetch_env!("DEPLOYEX_MONITORED_APP_NAME") |> String.replace("_", "-")

      secrets = fetch_aws_secret_id("deployex-#{monitored_app_name}-#{env}-secrets", request_opts)

      admin_hashed_password =
        keyword(:admin_hashed_password, secrets["DEPLOYEX_ADMIN_HASHED_PASSWORD"])

      secret_key_base = keyword(:secret_key_base, secrets["DEPLOYEX_SECRET_KEY_BASE"])
      erlang_cookie = secrets["DEPLOYEX_ERLANG_COOKIE"] |> String.to_atom()

      # Config Erlang Cookie if the node exist
      node = :erlang.node()

      if node != :nonode@nohost do
        :erlang.set_cookie(node, erlang_cookie)
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

  defp fetch_aws_secret_id(secret_id, opts) do
    secret_id
    |> build_request()
    |> ExAws.request(opts)
    |> parse_secrets()
  end

  defp build_request(secret_name) do
    JSON.new(
      :secretsmanager,
      %{
        data: %{"SecretId" => secret_name},
        headers: [
          {"x-amz-target", "secretsmanager.GetSecretValue"},
          {"content-type", "application/x-amz-json-1.1"}
        ]
      }
    )
  end

  defp parse_secrets({:ok, %{"SecretString" => json_secret}}) do
    Jason.decode!(json_secret)
  end

  defp parse_secrets({:error, {exception, reason}}) do
    Logger.error("#{inspect(exception)}: #{inspect(reason)}")
    %{}
  end
end
