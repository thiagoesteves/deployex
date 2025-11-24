defmodule Deployer.Upgrade.Deployex do
  @moduledoc """
  This module contains deployex hot upgrade commands to be 
  used by command line interface (CLI) or UI/UX
  """

  alias Deployer.Upgrade
  alias Deployer.Upgrade.Check
  alias Deployer.Upgrade.Execute
  alias Foundation.Catalog
  alias Foundation.Rpc
  alias Host.Commander

  require Logger

  @deployex_name "deployex"

  @spec check(download_path :: String.t()) :: {:ok, Check.t()} | {:error, any()}
  def check(download_path) do
    deployex_path = Application.fetch_env!(:foundation, :install_path)
    current_version = Application.spec(:foundation, :vsn)
    to_version = parse_version(download_path)

    # Temporary path to extract the release
    new_path = "/tmp/hotupgrade/#{@deployex_name}"
    File.rm_rf(new_path)
    File.mkdir_p(new_path)

    check = %Check{
      sname: @deployex_name,
      name: @deployex_name,
      language: "elixir",
      download_path: download_path,
      current_path: deployex_path,
      new_path: new_path,
      from_version: current_version,
      to_version: to_version
    }

    with {:ok, _} <-
           Commander.run("tar -xf  #{download_path} -C #{new_path}", [:sync, :stdout, :stderr]),
         {:ok, :hot_upgrade} <- Upgrade.check(check) do
      {:ok, check}
    else
      {:ok, type} ->
        {:error, type}

      reason ->
        Logger.warning(
          "Hot upgrade not supported for this release, #{current_version} -> #{to_version}, reason: #{inspect(reason)}"
        )

        reason
    end
  end

  @spec execute(download_path :: String.t()) :: :ok | {:error, any()}
  def execute(download_path) do
    current_version = Application.spec(:foundation, :vsn)
    to_version = parse_version(download_path)

    Logger.info("#{@deployex_name} hot upgrade requested: #{current_version} -> #{to_version}")

    with {:ok, check} <- check(download_path),
         %Execute{} = upgrade_data <-
           struct(%Execute{node: Node.self(), skip_make_permanent: true}, Map.from_struct(check)),
         :ok <- Upgrade.execute(upgrade_data) do
      Logger.warning("Hot upgrade in #{@deployex_name} installed with success")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Hot upgrade failed: #{inspect(reason)}")

        error
    end
  end

  @spec make_permanent(download_path :: String.t()) :: :ok | {:error, any()}
  def make_permanent(download_path) do
    node = Node.self()
    parsed_version = download_path |> parse_version()
    to_version = parsed_version |> to_charlist

    Upgrade.Application.notify_make_permanent(@deployex_name, parsed_version)

    case Rpc.call(node, :release_handler, :make_permanent, [to_version], :infinity) do
      :ok ->
        Catalog.add_version(%Catalog.Version{
          version: parsed_version,
          sname: @deployex_name,
          name: @deployex_name,
          deployment: :hot_upgrade,
          inserted_at: NaiveDateTime.utc_now()
        })

        Upgrade.Application.notify_complete_ok(@deployex_name)
        Logger.info("Release marked as permanent: #{to_version}")
        :ok

      reason ->
        Logger.error(
          "Error while trying to set a permanent version for #{to_version}, reason: #{inspect(reason)}"
        )

        Upgrade.Application.notify_error(@deployex_name, reason)

        {:error, reason}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp parse_version(download_path) do
    [_, to_version] =
      download_path
      |> Path.basename(".tar.gz")
      |> String.split("#{@deployex_name}-")

    to_version
  end
end
