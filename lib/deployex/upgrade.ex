defmodule Deployex.Upgrade do
  @moduledoc """
  This module will provide functions to update the application based on the appup.

  For a hotupgrade to happen, a few steps need to be followed:
  1. Ensure that .appup files are available. These files are generated during the release
     process when updating from an older version. For this project, these files are generated
     within the myapp application and then copied from Distillery.

  2. During deployment, the release app-new-version.tar.gz is copied to a directory named
     after the version under the current/releases folder, for example:
     /var/lib/deployex/service/myapp/current/releases/{new-version}/app-new-version.tar.gz

  3. A sequence of commands is executed by this module to create the relup file and install
     the release. Note that only upgrades are permitted in this project, and in the event of
     failure, the system will revert to a full deployment.

  4. ATTENTION:
     The sys.config file contains all application configurations and is not loaded during a
     hot upgrade. To address this, several steps are included in this module to load the new
     version of sys.config and utilize the RPC channel to execute runtime.exs and the config
     provider. It's important to note that these actions occur within the current version,
     meaning the system is not immediately prepared to execute hot upgrades when configuration
     changes occur.

  References:

  App up files generation
  https://github.com/bitwalker/distillery

  Relup and release installations
  https://github.com/erlware/relx/blob/main/priv/templates/install_upgrade_escript

  # For updating the config
  https://github.com/ausimian/castle/blob/main/lib/castle.ex
  """

  @timeout 300_000

  alias Deployex.Configuration

  require Logger

  ### ==========================================================================
  ### Public APIS
  ### ==========================================================================

  @spec run(binary() | charlist() | nil, binary() | charlist() | nil) :: :ok | {:error, any()}
  def run(from_version, to_version) when is_nil(from_version) or is_nil(to_version),
    do: {:error, :invalid_version}

  def run(from_version, to_version) when is_binary(from_version) or is_binary(to_version) do
    run(from_version |> to_charlist, to_version |> to_charlist)
  end

  def run(from_version, to_version) do
    with {:ok, node} <- connect(),
         :ok <- unpack_release(node, to_version),
         :ok <- make_relup(node, from_version, to_version),
         :ok <- check_install_release(node, to_version),
         :ok <- update_sys_config_from_installed_version(node, to_version),
         :ok <- install_release(node, to_version),
         :ok <- permfy(node, to_version),
         :ok <- return_original_sys_config(to_version) do
      Logger.info("Release upgrade executed with success from #{from_version} to #{to_version}")
      :ok
    else
      result ->
        result
    end
  end

  @spec which_releases(atom()) :: list()
  def which_releases(node) do
    releases = :rpc.call(node, :release_handler, :which_releases, [], @timeout)

    releases |> Enum.map(fn {_name, version, _modules, status} -> {status, version} end)
  end

  @spec update_sys_config_from_installed_version(atom(), charlist()) :: :ok | {:error, any()}
  def update_sys_config_from_installed_version(node, to_version) do
    rel_vsn_dir = "#{Configuration.current_path()}/releases/#{to_version}"
    sys_config_path = Path.join(rel_vsn_dir, "sys.config")
    original_sys_config_file = Path.join(rel_vsn_dir, "original.sys.config")
    # Read the build time config from build.config
    {:ok, [sys_config]} = :file.consult(sys_config_path)
    # In this step, it will run the runtime.exs and Config Providers for the old version
    sys_config =
      sys_config
      |> Keyword.get(:elixir)
      |> Keyword.get(:config_provider_init)
      |> Map.get(:providers)
      |> Enum.reduce(sys_config, fn {mod, arg}, cfg ->
        :rpc.call(node, mod, :load, [cfg, arg], @timeout)
      end)

    with :ok <- File.rename(sys_config_path, original_sys_config_file),
         :ok <-
           File.write(sys_config_path, :io_lib.format(~c"%% coding: utf-8~n~tp.~n", [sys_config])) do
      :ok
    else
      reason ->
        Logger.error(
          "Error while loading sys.config to: #{to_version}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec return_original_sys_config(charlist()) :: :ok | {:error, atom()}
  def return_original_sys_config(to_version) do
    rel_vsn_dir = "#{Configuration.current_path()}/releases/#{to_version}"
    sys_config_path = Path.join(rel_vsn_dir, "sys.config")
    original_sys_config_file = Path.join(rel_vsn_dir, "original.sys.config")

    File.rename(original_sys_config_file, sys_config_path)
  end

  @spec check(binary(), binary() | charlist() | nil, binary() | charlist()) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def check(download_path, from_version, to_version)
      when is_binary(from_version) or is_binary(to_version) do
    check(download_path, from_version |> to_charlist, to_version |> to_charlist)
  end

  def check(download_path, from_version, to_version) do
    monitored_app = Configuration.monitored_app()

    with [file_path] <-
           Path.wildcard("#{Configuration.new_path()}/lib/#{monitored_app}-*/ebin/*.appup"),
         :ok <- check_app_up(file_path, from_version, to_version) do
      Logger.warning("HOT UPGRADE version DETECTED, from: #{from_version} to: #{to_version}")

      # Copy binary to the release folder under the version directory
      dest_dir = "#{Configuration.current_path()}/releases/#{to_version}"

      File.rm_rf(dest_dir)

      {"", 0} = System.cmd("mkdir", [dest_dir])

      {"", 0} = System.cmd("cp", [download_path, "#{dest_dir}/#{monitored_app}.tar.gz"])

      {:ok, :hot_upgrade}
    else
      result ->
        Logger.warning(
          "HOT UPGRADE version NOT DETECTED, full deployment required, result: #{inspect(result)}"
        )

        {:ok, :full_deployment}
    end
  end

  @spec check_app_up(binary(), charlist(), charlist()) ::
          :ok | {:error, :error_reading_file | :no_match_versions}
  def check_app_up(file_path, from_version, to_version) do
    with {:ok, app_up_list} <- :file.consult(file_path),
         true <- match_version_upgrade?(app_up_list, from_version, to_version) do
      :ok
    else
      false ->
        {:error, :no_match_versions}

      reason ->
        Logger.error("Error while reading appup file, reason: #{inspect(reason)}")

        {:error, :error_reading_file}
    end
  end

  @spec unpack_release(atom(), charlist()) :: :ok | {:error, any()}
  def unpack_release(node, to_version) do
    release_link = "#{to_version}/#{Configuration.monitored_app()}" |> to_charlist

    case :rpc.call(node, :release_handler, :unpack_release, [release_link], @timeout) do
      {:ok, version} ->
        Logger.info("Unpacked successfully: #{inspect(version)}")
        :ok

      reason ->
        Logger.error(
          "Error while unpacking the release #{to_version}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec make_relup(atom(), charlist(), charlist()) :: :ok | {:error, :make_relup}
  def make_relup(node, from_version, to_version) do
    root = root_dir(node)

    :rpc.call(
      node,
      :systools,
      :make_relup,
      [
        root ++ ~c"/releases/#{Configuration.monitored_app()}-" ++ to_version,
        [root ++ ~c"/releases/#{Configuration.monitored_app()}-" ++ from_version],
        [root ++ ~c"/releases/#{Configuration.monitored_app()}-" ++ from_version],
        [
          {:path,
           [root ++ ~c"/lib/*/ebin", root ++ ~c"/releases/*/#{Configuration.monitored_app()}"]},
          {:outdir, [root ++ ~c"/releases/" ++ to_version]}
        ]
      ],
      @timeout
    )
    |> case do
      :ok ->
        :ok

      reason ->
        Logger.error("systools:make_relup failed, reason: #{inspect(reason)}")
        {:error, :make_relup}
    end
  end

  @spec check_install_release(atom(), charlist()) :: :ok | {:error, any()}
  def check_install_release(node, to_version) do
    case :rpc.call(node, :release_handler, :check_install_release, [to_version], @timeout) do
      {:ok, _other, _desc} ->
        :ok

      {:error, reason} = result ->
        Logger.error("release_handler:check_install_release failed, reason: #{inspect(reason)}")
        result
    end
  end

  @spec install_release(atom(), charlist()) :: :ok | {:error, any()}
  def install_release(node, to_version) do
    case :rpc.call(
           node,
           :release_handler,
           :install_release,
           [to_version, [{:update_paths, true}]],
           @timeout
         ) do
      {:ok, _, _} ->
        Logger.info("Installed Release: #{inspect(to_version)}")
        :ok

      {:error, reason} = result ->
        Logger.error("release_handler:install_release failed, reason: #{inspect(reason)}")
        result
    end
  end

  @spec permfy(atom(), charlist()) :: :ok | {:error, any()}
  def permfy(node, version) do
    case :rpc.call(node, :release_handler, :make_permanent, [version], @timeout) do
      :ok ->
        Logger.info("Made release permanent: #{version}")
        :ok

      reason ->
        Logger.error(
          "Error while trying to set a permanent version for #{version}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec root_dir(atom()) :: any()
  def root_dir(node), do: :rpc.call(node, :code, :root_dir, [])

  @spec connect() :: {:error, :not_connecting} | {:ok, atom()}
  def connect do
    {:ok, hostname} = :inet.gethostname()
    node = :"#{Configuration.monitored_app()}@#{hostname}"

    case Node.connect(node) do
      true ->
        {:ok, node}

      false ->
        Logger.error("Error while trying to connect with node: #{inspect(node)}")
        {:error, :not_connecting}
    end
  end

  defp match_version_upgrade?(list, from_version, to_version) do
    Enum.any?(list, fn
      {^to_version, [{^from_version, _}], [{^from_version, _}]} ->
        true

      _app_up ->
        false
    end)
  end
end
