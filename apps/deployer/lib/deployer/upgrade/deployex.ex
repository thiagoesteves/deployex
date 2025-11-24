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

  @doc """
  Performs a hot upgrade check only

  This function orchestrates a hot code upgrade by:
  1. Extracting the new release tarball to a temporary directory
  2. Checking if the release supports hot upgrade (via .appup files)

  ## Parameters

    * `download_path` - Path to the release tarball (e.g., "/tmp/deployex-0.8.1.tar.gz")

  ## Returns

    * `:ok` - Hot upgrade completed successfully (but not yet permanent)
    * `{:error, reason}` - Hot upgrade failed or not available

  ## Examples

      iex> Deployer.Deployex.hot_upgrade("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      :ok
      
      iex> Deployer.Deployex.make_permanent("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      :ok
  """
  @spec hot_upgrade_check(download_path :: String.t()) :: {:ok, Check.t()} | {:error, any()}
  def hot_upgrade_check(download_path) do
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

  @doc """
  Performs a hot upgrade of the DeployEx application itself.

  This function orchestrates a hot code upgrade by:
  1. Extracting the new release tarball to a temporary directory
  2. Checking if the release supports hot upgrade (via .appup files)
  3. Executing the hot upgrade sequence (unpack, relup, check, install)
  4. Skipping the `make_permanent` step (must be called separately for self-upgrades)

  ## Parameters

    * `download_path` - Path to the release tarball (e.g., "/tmp/deployex-0.8.1.tar.gz")

  ## Returns

    * `:ok` - Hot upgrade completed successfully (but not yet permanent)
    * `{:error, reason}` - Hot upgrade failed or not available

  ## Notes

  For self-upgrades, `make_permanent/1` MUST be called separately after this function
  succeeds. Including it in the upgrade sequence causes the calling process to crash,
  even though the upgrade applies successfully. This occurs because the calling process
  is part of the application being upgraded and gets killed when `make_permanent` 
  triggers supervisor restarts.

  ## Examples

      iex> Deployer.Deployex.hot_upgrade("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      :ok
      
      iex> Deployer.Deployex.make_permanent("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      :ok
  """
  @spec hot_upgrade(download_path :: String.t()) :: :ok | {:error, any()}
  def hot_upgrade(download_path) do
    current_version = Application.spec(:foundation, :vsn)
    to_version = parse_version(download_path)

    Logger.info("#{@deployex_name} hot upgrade requested: #{current_version} -> #{to_version}")

    with {:ok, check} <- hot_upgrade_check(download_path),
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

  @doc """
  Makes a previously installed release permanent.

  This function marks the specified release version as permanent using the Erlang/OTP
  release handler. A permanent release will be the default version loaded on VM restart.

  ## Parameters

    * `download_path` - Path to the release tarball used to determine the version
                        (e.g., "/tmp/deployex-0.8.1.tar.gz")

  ## Returns

    * `:ok` - Release successfully marked as permanent
    * `{:error, reason}` - Failed to make the release permanent

  ## Notes

  For DeployEx self-upgrades, this function must be called separately after `hot_upgrade/1`
  succeeds. Calling it within the upgrade sequence causes process crashes.

  For managed applications (non-self-upgrades), this is typically called automatically
  as part of the upgrade sequence.

  ## Examples

      iex> Deployer.Deployex.make_permanent("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      :ok
      
      iex> Deployer.Deployex.make_permanent("/path/to/invalid-release.tar.gz")
      {:error, {:no_such_release, '0.8.1'}}
  """
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
