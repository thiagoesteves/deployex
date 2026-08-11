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
    with {:ok, to_version} <- parse_version(download_path) do
      check_release(download_path, to_version)
    end
  end

  defp check_release(download_path, to_version) do
    deployex_path = Application.fetch_env!(:foundation, :install_path)
    current_version = Application.spec(:foundation, :vsn)

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
         :ok <- check_otp_version(new_path),
         {:ok, %Check{deploy: :hot_upgrade} = check} <- HotUpgradeApp.check(check) do
      {:ok, check}
    else
      {:ok, %Check{deploy: :full_deployment}} ->
        Logger.warning(
          "Hot upgrade not supported for this release, #{current_version} -> #{to_version}, " <>
            "it requires a full deployment"
        )

        {:error, :full_deployment}

      {:error, {:otp_mismatch, _versions} = reason} ->
        {:error, reason}

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
    with {:ok, to_version} <- parse_version(download_path) do
      execute_release(download_path, to_version, options)
    end
  end

  defp execute_release(download_path, to_version, options) do
    sync_execution = Keyword.get(options, :sync_execution, true)
    make_permanent_async = Keyword.get(options, :make_permanent_async, true)
    current_version = Application.spec(:foundation, :vsn)

    Logger.info("#{@deployex_name} hot upgrade requested: #{current_version} -> #{to_version}")

    after_async_make_permanent = fn ->
      Catalog.add_version(%Catalog.Version{
        version: to_version,
        sname: @deployex_name,
        name: @deployex_name,
        deployment: :hot_upgrade,
        inserted_at: NaiveDateTime.utc_now()
      })
    end

    # A failure from check/1 is refused before the upgrade is attempted and reports itself,
    # only the upgrade's own outcome is logged here
    with {:ok, check} <- check(download_path) do
      upgrade_data =
        struct(
          %Execute{
            node: Node.self(),
            make_permanent_async: make_permanent_async,
            sync_execution: sync_execution,
            after_async_make_permanent: after_async_make_permanent
          },
          Map.from_struct(check)
        )

      case HotUpgradeApp.execute(upgrade_data) do
        :ok ->
          log_requested(sync_execution, current_version, to_version)
          :ok

        error ->
          log_failure(error, current_version, to_version)
          error
      end
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  # Nothing here restarts DeployEx, it carries on serving either way, but which code it is
  # serving depends on how far the upgrade got. Before install_release nothing was touched
  # and the unpacked release is removed, so the previous version is still the one running
  defp log_failure({:error, {:not_installed, reason}}, current_version, to_version) do
    Logger.error(
      "Hot upgrade in #{@deployex_name} failed, #{current_version} -> #{to_version}, " <>
        "reason: #{inspect(reason)}. Nothing was installed, #{@deployex_name} is still " <>
        "running #{current_version}."
    )
  end

  # Past install_release the new code is already loaded, so claiming the previous version is
  # still running would be wrong
  defp log_failure({:error, reason}, current_version, to_version) do
    Logger.error(
      "Hot upgrade in #{@deployex_name} failed, #{current_version} -> #{to_version}, " <>
        "reason: #{inspect(reason)}. The release was installed before it failed, " <>
        "#{@deployex_name} may already be running #{to_version}."
    )
  end

  # NOTE: an asynchronous execution is a cast, so :ok means the request was accepted and
  #       says nothing about the upgrade itself, which has not run yet. Only the
  #       synchronous path can report an installation. The asynchronous outcome arrives
  #       later, on the hot upgrade events topic.
  defp log_requested(false, current_version, to_version) do
    Logger.info(
      "Hot upgrade in #{@deployex_name} started, #{current_version} -> #{to_version}, " <>
        "the outcome follows"
    )
  end

  defp log_requested(true, current_version, to_version) do
    Logger.warning(
      "Hot upgrade in #{@deployex_name} installed with success, #{current_version} -> #{to_version}"
    )
  end

  # A hot upgrade replaces application code inside the running VM, it cannot replace the VM
  # underneath it. A release built for another OTP brings a different Erlang and Elixir, and
  # systools:make_relup needs an appup for every application whose version changes, which
  # neither ships. The upgrade fails after the release is unpacked, complaining about a
  # missing appup and saying nothing about the wrong artifact having been chosen.
  #
  # The release bundles its own erts directory, so its OTP is known before anything is
  # installed. The erts version identifies the OTP release, OTP 27 ships erts 15 and OTP 28
  # ships erts 16, so comparing it against the running one is the same check.
  defp check_otp_version(new_path) do
    running_erts = to_string(:erlang.system_info(:version))

    case Path.wildcard("#{new_path}/erts-*") do
      [directory] ->
        package_erts = directory |> Path.basename() |> String.replace_prefix("erts-", "")
        compare_otp_version(running_erts, package_erts)

      _ ->
        # No bundled erts to compare, leave it to the checks that follow
        :ok
    end
  end

  defp compare_otp_version(running_erts, package_erts) when running_erts == package_erts,
    do: :ok

  defp compare_otp_version(running_erts, package_erts) do
    versions = %{
      running_otp: to_string(:erlang.system_info(:otp_release)),
      running_erts: running_erts,
      package_erts: package_erts
    }

    Logger.error("""
    Hot upgrade refused, this release was built for a different OTP. #{@deployex_name} runs \
    OTP #{versions.running_otp} with erts #{running_erts} and the release brings erts \
    #{package_erts}. A hot upgrade cannot replace the runtime under a running system. Use \
    the artifact matching the otp_version this installation runs, or apply it as a full \
    deployment.\
    """)

    {:error, {:otp_mismatch, versions}}
  end

  # A release file is named deployex-<version>.tar.gz and the version is read from the name,
  # there is nothing else to read it from before the file is extracted. Any other name is not
  # a DeployEx release, most often a monitored application's package picked by mistake, and
  # has to be refused here rather than while splitting the name apart
  defp parse_version(download_path) do
    filename = Path.basename(download_path, ".tar.gz")

    case String.split(filename, "#{@deployex_name}-") do
      [_, to_version] when to_version != "" ->
        {:ok, to_version}

      _ ->
        Logger.error(
          "Hot upgrade refused, #{inspect(Path.basename(download_path))} is not a " <>
            "#{@deployex_name} release. Expected a file named #{@deployex_name}-<version>.tar.gz."
        )

        {:error, :invalid_release_file}
    end
  end
end
