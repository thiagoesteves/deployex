defmodule Deployer.HotUpgrade.Deployex do
  @moduledoc """
  This module contains deployex hot upgrade commands to be 
  used by command line interface (CLI) or UI/UX
  """

  alias Deployer.HotUpgrade.Application, as: HotUpgradeApp
  alias Deployer.HotUpgrade.Check
  alias Deployer.HotUpgrade.Execute
  alias Foundation.Catalog
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
         {:ok, :hot_upgrade} <- HotUpgradeApp.check(check) do
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

  @spec execute(download_path :: String.t(), options :: Keyword.t()) ::
          :ok | {:error, any()}
  def execute(download_path, options) do
    sync_execution = Keyword.get(options, :sync_execution, true)
    make_permanent_async = Keyword.get(options, :make_permanent_async, true)
    current_version = Application.spec(:foundation, :vsn)
    to_version = parse_version(download_path)

    Logger.info("#{@deployex_name} hot upgrade requested: #{current_version} -> #{to_version}")

    after_asyn_make_permanent = fn ->
      Catalog.add_version(%Catalog.Version{
        version: to_version,
        sname: @deployex_name,
        name: @deployex_name,
        deployment: :hot_upgrade,
        inserted_at: NaiveDateTime.utc_now()
      })
    end

    with {:ok, check} <- check(download_path),
         %Execute{} = upgrade_data <-
           struct(
             %Execute{
               node: Node.self(),
               make_permanent_async: make_permanent_async,
               sync_execution: sync_execution,
               after_asyn_make_permanent: after_asyn_make_permanent
             },
             Map.from_struct(check)
           ),
         :ok <- HotUpgradeApp.execute(upgrade_data) do
      Logger.warning("Hot upgrade in #{@deployex_name} installed with success")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Hot upgrade failed: #{inspect(reason)}")

        error
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
