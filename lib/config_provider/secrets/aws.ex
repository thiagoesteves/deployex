defmodule Deployex.ConfigProvider.Secrets.Aws do
  @moduledoc """
  Adapter implementation for retrieving secrets from AWS secret manager
  """
  @behaviour Deployex.ConfigProvider.Secrets.Adapter

  require Logger

  alias ExAws.Operation.JSON

  @doc """
  secrets/2.

  Args:
    - secret_path_id: Path to the secret content, e. g. deployex-{app}-prod-secrets
    - opts is just the return value of init/1.
  """
  @impl true
  def secrets(_config, path, opts) do
    region = System.fetch_env!("AWS_REGION")
    request_opts = Keyword.merge(opts, region: region)

    fetch_aws_secret_id(path, request_opts)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

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

  defp fetch_aws_secret_id(secret_path_id, opts) do
    secret_path_id
    |> build_request()
    |> ExAws.request(opts)
    |> case do
      {:ok, %{"SecretString" => json_secret}} ->
        Jason.decode!(json_secret)

      reason ->
        raise "Fail to retrieve secrests with reason #{inspect(reason)}"
    end
  end
end
