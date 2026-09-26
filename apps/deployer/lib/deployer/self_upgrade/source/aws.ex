defmodule Deployer.SelfUpgrade.Source.Aws do
  @moduledoc """
  Reads the desired version from the instance's own `deployex_version` tag through IMDSv2.

  Requires the instance to enable metadata tags:
  `metadata_options { instance_metadata_tags = "enabled" }`.
  """

  @behaviour Deployer.SelfUpgrade.Source.Adapter

  @impl true
  @spec desired_version() :: {:ok, String.t()} | :none | {:error, any()}
  def desired_version do
    with {:ok, token} <- client().token(),
         {:ok, version} <- client().tag(token) do
      {:ok, String.trim(version)}
    else
      {:error, :not_found} -> :none
      {:error, _} = error -> error
    end
  end

  defp client, do: Application.get_env(:deployer, __MODULE__)[:client] || __MODULE__.Imds
end

defmodule Deployer.SelfUpgrade.Source.Aws.Imds do
  @moduledoc false

  @base "http://169.254.169.254"
  @ttl "21600"
  @tag "deployex_version"

  def token do
    req =
      Finch.build(:put, "#{@base}/latest/api/token", [
        {"x-aws-ec2-metadata-token-ttl-seconds", @ttl}
      ])

    case Finch.request(req, Deployer.Finch) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      other -> {:error, other}
    end
  end

  def tag(token) do
    req =
      Finch.build(:get, "#{@base}/latest/meta-data/tags/instance/#{@tag}", [
        {"x-aws-ec2-metadata-token", token}
      ])

    case Finch.request(req, Deployer.Finch) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> {:error, other}
    end
  end
end
