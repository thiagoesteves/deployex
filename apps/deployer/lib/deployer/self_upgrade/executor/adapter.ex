defmodule Deployer.SelfUpgrade.Executor.Adapter do
  @moduledoc """
  Behaviour for running a DeployEx self-upgrade to a target version.
  """

  @callback hot_upgrade(version :: String.t()) :: :ok | {:error, any()}
end
