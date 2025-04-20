defmodule Deployex.ConfigProvider.Secrets.Aws do
  @moduledoc """
  Adapter implementation for retrieving secrets from AWS secret manager
  """
  @behaviour Deployex.ConfigProvider.Secrets.Adapter
  @behaviour ExAws.Request.HttpClient

  require Logger

  alias ExAws.Operation.JSON

  @doc """
  secrets/3.

  Args:
    - The current config
    - secret_path_id: Path to the secret content, e. g. deployex-{app}-prod-secrets
    - opts is just the return value of init/1.
  """
  @impl Deployex.ConfigProvider.Secrets.Adapter
  def secrets(config, path, opts) do
    region = Keyword.get(config, :ex_aws) |> Keyword.get(:region)

    request_opts =
      Keyword.merge(opts, region: region, http_client: Deployex.ConfigProvider.Secrets.Aws)

    {:ok, _} = Application.ensure_all_started(:finch)
    {:ok, _} = Application.ensure_all_started(:ex_aws)

    children = [
      {Finch, name: FinchAwsSecretManagerClient}
    ]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    data = fetch_aws_secret_id(path, request_opts)

    Supervisor.stop(sup, :normal)

    data
  end

  @impl ExAws.Request.HttpClient
  def request(method, url, body, headers, _http_opts) do
    case Finch.build(method, url, headers, body)
         |> Finch.request(FinchAwsSecretManagerClient) do
      {:ok, resp} ->
        {:ok, %{status_code: resp.status, body: resp.body, headers: resp.headers}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
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
