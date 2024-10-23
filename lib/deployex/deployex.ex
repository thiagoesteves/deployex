defmodule Deployex do
  @moduledoc """
  DeployEx is a lightweight tool designed for managing deployments in Elixir
  and Gleam applications without relying on additional deployment tools like
  Docker or Kubernetes. Its primary goal is to utilize the release package
  for executing full deployments or hot-upgrades, depending on the package's
  content, while leveraging OTP distribution for monitoring and data extraction
  """

  alias Deployex.OpSys

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
  def force_terminate(sleep_time \\ 300) do
    Logger.warning("Deployex was requested to terminate, see you soon!!!")

    :timer.sleep(sleep_time)

    OpSys.run(
      "kill -9 $(ps -ax | grep \"/opt/deployex/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
      [:sync, :stdout, :stderr]
    )

    :ok
  end
end
