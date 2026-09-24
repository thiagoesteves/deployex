defmodule Deployer.SelfUpgrade.Executor do
  @moduledoc """
  Runs a DeployEx self-upgrade through the configured executor adapter.
  """

  @behaviour Deployer.SelfUpgrade.Executor.Adapter

  @impl true
  @spec hot_upgrade(String.t()) :: :ok | {:error, any()}
  def hot_upgrade(version), do: default().hot_upgrade(version)

  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
