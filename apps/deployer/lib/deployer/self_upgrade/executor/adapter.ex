defmodule Deployer.SelfUpgrade.Executor.Adapter do
  @moduledoc """
  Behaviour for building the command that runs a DeployEx self-upgrade to a target version.

  The adapter only builds the command. The worker runs it in a Task that calls
  `System.cmd/3` directly, so the Task holds no DeployEx code while it waits and a
  relup that changes DeployEx modules cannot purge that code out from under it.
  """

  @type command :: {String.t(), [String.t()], keyword()}

  @callback hot_upgrade_command(version :: String.t()) :: {:ok, command()} | {:error, any()}
end
