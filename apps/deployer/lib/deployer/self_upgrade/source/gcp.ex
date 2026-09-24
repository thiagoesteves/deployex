defmodule Deployer.SelfUpgrade.Source.Gcp do
  @moduledoc """
  Reads the desired version from the instance's own `deployex_version` metadata attribute
  through the GCP metadata server.

  Requires the instance to carry a `deployex_version` metadata attribute.
  """

  @behaviour Deployer.SelfUpgrade.Source.Adapter

  @impl true
  @spec desired_version() :: {:ok, String.t()} | :none | {:error, any()}
  def desired_version do
    case client().attribute() do
      {:ok, value} -> {:ok, String.trim(value)}
      {:error, :not_found} -> :none
      {:error, _} = error -> error
    end
  end

  defp client, do: Application.get_env(:deployer, __MODULE__)[:client] || __MODULE__.Metadata
end

defmodule Deployer.SelfUpgrade.Source.Gcp.Metadata do
  @moduledoc false

  @base "http://metadata.google.internal/computeMetadata/v1"
  @attribute "deployex_version"

  def attribute do
    req =
      Finch.build(:get, "#{@base}/instance/attributes/#{@attribute}", [
        {"metadata-flavor", "Google"}
      ])

    case Finch.request(req, Deployer.Finch) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> {:error, other}
    end
  end
end
