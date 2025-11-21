defmodule Deployer.Deployex do
  @moduledoc """
  This module contains deployex application specific commands
  """

  alias Deployer.Upgrade
  alias Deployer.Upgrade.Check
  alias Deployer.Upgrade.Execute
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

    deployex_path = Application.fetch_env!(:foundation, :install_path)

    Commander.run(
      "kill -9 $(ps -ax | grep \"#{deployex_path}/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
      [:sync, :stdout, :stderr]
    )

    :ok
  end

  @spec hot_upgrade(download_path :: String.t()) :: :ok
  def hot_upgrade(download_path) do
    deployex_path = Application.fetch_env!(:foundation, :install_path)
    current_version = Application.spec(:deployer, :vsn)
    node = Node.self()
    name = "deployex"

    [_, to_version] =
      download_path
      |> Path.basename(".tar.gz")
      |> String.split("#{name}-")

    Logger.warning("DeployEx hotupgrade from #{current_version} to #{to_version}")

    # Temporary path to extract the release
    new_path = "/tmp/hotupgrade/#{name}"
    File.rm_rf(new_path)
    File.mkdir_p(new_path)

    check = %Check{
      sname: name,
      name: name,
      language: "elixir",
      download_path: download_path,
      current_path: deployex_path,
      new_path: new_path,
      from_version: current_version,
      to_version: to_version
    }

    with {"", 0} <- System.cmd("tar", ["-x", "-f", download_path, "-C", new_path]),
         {:ok, :hot_upgrade} <- Upgrade.check(check),
         %Execute{} = upgrade_data <- struct(%Execute{node: node}, Map.from_struct(check)),
         :ok <- Upgrade.execute(upgrade_data) do
      Logger.warning("Hot upgrade in deployex executed with success")
    else
      reason ->
        Logger.error("Error while executing hotupgrade, reason: #{inspect(reason)}")
    end
  end
end
