defmodule Deployer.Deployex do
  @moduledoc """
  This module contains deployex application specific commands
  """

  alias Host.Commander

  require Logger

  ### ==========================================================================
  ### Public Functions
  ### ==========================================================================
  @doc """
  This function forces DeployEx to terminate. If DeployEx is installed as a
  systemd service, it will automatically restart. This function has not effect
  when running locally.
  """
  @spec force_terminate(non_neg_integer()) :: :ok
  def force_terminate(sleep_time) do
    Logger.warning("Deployex was requested to terminate, see you soon!!!")

    :timer.sleep(sleep_time)

    Commander.run(
      "kill -9 $(ps -ax | grep \"/opt/deployex/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
      [:sync, :stdout, :stderr]
    )

    :ok
  end
end
