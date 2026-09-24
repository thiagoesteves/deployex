defmodule Deployer.SelfUpgrade.Source do
  @moduledoc "Reads the desired DeployEx version from the configured source adapter."

  @behaviour Deployer.SelfUpgrade.Source.Adapter

  @impl true
  def desired_version, do: default().desired_version()

  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
