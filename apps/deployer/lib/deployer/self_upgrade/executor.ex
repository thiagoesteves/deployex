defmodule Deployer.SelfUpgrade.Executor do
  @moduledoc """
  Builds the DeployEx self-upgrade command through the configured executor adapter.
  """

  @behaviour Deployer.SelfUpgrade.Executor.Adapter

  @impl true
  @spec hot_upgrade_command(String.t()) ::
          {:ok, Deployer.SelfUpgrade.Executor.Adapter.command()} | {:error, any()}
  def hot_upgrade_command(version), do: default().hot_upgrade_command(version)

  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
