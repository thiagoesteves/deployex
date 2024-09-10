defmodule Deployex.ConfigProvider.Secrets.Gcp do
  @moduledoc """
  Adapter implementation for retrieving secrets from Gcp
  """
  @behaviour Deployex.ConfigProvider.Secrets.Adapter

  require Logger

  # alias ExAws.Operation.JSON

  @doc """
  secrets/2.

  Args:
    - secret_path_id: Path to the secret content, e. g. deployex-{app}-prod-secrets
    - opts is just the return value of init/1.
  """
  @impl true
  def secrets(secret_path, _opts) do
    goth_name = Deployex.SecretManager.Goth

    credentials =
      "GOOGLE_APPLICATION_CREDENTIALS" |> System.fetch_env!() |> File.read!() |> Jason.decode!()

    {:ok, _} = Application.ensure_all_started(:goth)

    source = {:service_account, credentials}

    children = [
      {Finch, name: FinchSecretManagerClient},
      {Goth, name: goth_name, source: source}
    ]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    {:ok, project_id} = Goth.Config.get(:project_id)
    token = Goth.fetch!(goth_name, 5_000)

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{token.token}"},
      {"accept", "application/json"}
    ]

    path =
      "https://secretmanager.googleapis.com/v1/projects/#{project_id}/secrets/#{secret_path}/versions/latest:access"

    data =
      :get
      |> Finch.build(path, headers, [])
      |> Finch.request(FinchSecretManagerClient)
      |> case do
        {:ok, %Finch.Response{body: body}} ->
          Jason.decode!(body)["payload"]["data"]
          |> Base.decode64!()
          |> Jason.decode!()

        reason ->
          raise "Fail to retrieve secrests with reason #{inspect(reason)}"
      end

    Supervisor.stop(sup, :normal)

    data
  end
end
