defmodule Deployex.Upgrade.Application do
  @moduledoc """
  This module will provide functions to update the application based on the appup.

  For a hotupgrade to happen, a few steps need to be followed:
  1. Ensure that .appup files are available. These files are generated during the release process
     when updating from an older version. Deployex was designed to consume appup files generated
     by these libraries:
       a. [Jellyfish](https://github.com/thiagoesteves/jellyfish) (For Elixir apps)
       a. [Rebar3 appup plugin](https://github.com/lrascao/rebar3_appup_plugin) (For Erlang apps)

  2. During deployment, the release app-new-version.tar.gz is copied to a directory named
     after the version under the current/releases folder, for example:
     /var/lib/deployex/service/myapp/current/{instance}/releases/{new-version}/app-new-version.tar.gz

  3. A sequence of commands is executed by this module:
       a. Unpack a release using release_handler:unpack_release
       b. Create a relup file using systools:make_relup
       c. Check Intall release using release_handler:check_install_release
         i. Request via RPC to run  ConfigProvider and Runtime and populate sys.config (Only ELixir)
       d. Install the release using release_handler:install_release
       e. Make the release permanent using release_handler:make_permanent
         i. Return original empty sys.config (Only ELixir)

    Note that only upgrades are permitted in this project, and in the event of
     failure, the system will revert to a full deployment.

  4. ATTENTION:
     The sys.config file contains all application configurations and is not loaded during a
     hot upgrade. For Elixir applications, Config Provider and Runtime are codes that executes
     when the applicaiton is starting and are required for fetching information.
     To address this, several steps are included in this module to load the new
     version of sys.config and utilize the RPC channel to execute runtime.exs and the config
     provider. It's important to note that these actions occur within the current version,
     meaning the system is not immediately prepared to execute hot upgrades when configuration
     changes occur.

  References:

  * https://learnyousomeerlang.com/relups
  * https://www.erlang.org/doc/system/appup_cookbook.html
  * https://github.com/lrascao/rebar3_appup_plugin
  * https://lrascao.github.io/automatic-release-upgrades-in-erlang/
  * https://rebar3.org/docs/deployment/releases/
  * https://rebar3.org/docs/configuration/plugins/
  * https://github.com/erlware/relx/blob/main/priv/templates/install_upgrade_escript
  * https://github.com/bitwalker/distillery (elixir oriented)
  * https://github.com/ausimian/castle/blob/main/lib/castle.ex (elixir oriented)
  """

  @timeout 300_000

  alias Deployex.Rpc
  alias Deployex.Storage

  @behaviour Deployex.Upgrade.Adapter

  require Logger

  ### ==========================================================================
  ### Public APIS
  ### ==========================================================================

  @impl true
  @spec execute(
          integer(),
          String.t(),
          String.t(),
          binary() | charlist() | nil,
          binary() | charlist() | nil
        ) ::
          :ok | {:error, any()}
  def execute(_instance, _app_name, _app_lang, from_version, to_version)
      when is_nil(from_version) or is_nil(to_version),
      do: {:error, :invalid_version}

  def execute(instance, app_name, app_lang, from_version, to_version)
      when is_binary(from_version) or is_binary(to_version) do
    execute(instance, app_name, app_lang, from_version |> to_charlist, to_version |> to_charlist)
  end

  def execute(instance, app_name, app_lang, from_version, to_version) do
    with {:ok, node} <- connect(instance),
         :ok <- unpack_release(node, app_name, to_version),
         :ok <- make_relup(node, instance, app_name, app_lang, from_version, to_version),
         :ok <- check_install_release(node, to_version),
         :ok <- update_sys_config_from_installed_version(node, instance, app_lang, to_version),
         :ok <- install_release(node, to_version),
         :ok <- permfy(node, instance, app_name, app_lang, to_version),
         :ok <- return_original_sys_config(instance, app_lang, to_version) do
      message =
        "Release upgrade executed with success at instance: #{instance} from: #{from_version} to: #{to_version}"

      Logger.info(message)

      :ok
    end
  end

  @spec which_releases(atom()) :: list()
  def which_releases(node) do
    releases = Rpc.call(node, :release_handler, :which_releases, [], @timeout)

    releases |> Enum.map(fn {_name, version, _modules, status} -> {status, version} end)
  end

  @spec update_sys_config_from_installed_version(atom(), integer(), String.t(), charlist()) ::
          :ok | {:error, any()}
  def update_sys_config_from_installed_version(node, instance, "elixir", to_version) do
    rel_vsn_dir = "#{Storage.current_path(instance)}/releases/#{to_version}"
    sys_config_path = "#{rel_vsn_dir}/sys.config"
    original_sys_config_file = "#{rel_vsn_dir}/original.sys.config"
    # Read the build time config from build.config
    {:ok, [sys_config]} = :file.consult(sys_config_path)
    # In this step, it will run the runtime.exs and Config Providers for the current version
    sys_config =
      sys_config
      |> Keyword.get(:elixir)
      |> Keyword.get(:config_provider_init)
      |> Map.get(:providers)
      |> Enum.reduce(sys_config, fn {mod, arg}, cfg ->
        Rpc.call(node, mod, :load, [cfg, arg], @timeout)
      end)

    with :ok <- File.rename(sys_config_path, original_sys_config_file),
         :ok <-
           File.write(sys_config_path, :io_lib.format(~c"%% coding: utf-8~n~tp.~n", [sys_config])) do
      :ok
    else
      {:error, reason} ->
        Logger.error(
          "Error while updating sys.config to: #{to_version}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def update_sys_config_from_installed_version(_node, _instance, _app_lang, _to_version), do: :ok

  @spec return_original_sys_config(integer(), String.t(), charlist()) :: :ok | {:error, atom()}
  def return_original_sys_config(instance, "elixir", to_version) do
    rel_vsn_dir = "#{Storage.current_path(instance)}/releases/#{to_version}"
    sys_config_path = "#{rel_vsn_dir}/sys.config"
    original_sys_config_file = "#{rel_vsn_dir}/original.sys.config"

    File.rename(original_sys_config_file, sys_config_path)
  end

  def return_original_sys_config(_instance, _app_lang, _to_version), do: :ok

  @impl true
  @spec check(
          integer(),
          String.t(),
          String.t(),
          binary(),
          binary() | charlist() | nil,
          binary() | charlist()
        ) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def check(instance, app_name, app_lang, download_path, from_version, to_version)
      when is_binary(from_version) or is_binary(to_version) do
    check(
      instance,
      app_name,
      app_lang,
      download_path,
      from_version |> to_charlist,
      to_version |> to_charlist
    )
  end

  def check(instance, app_name, app_lang, download_path, from_version, to_version) do
    cp_appup_priv_to_ebin = fn ->
      priv_app_up_file =
        "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/priv/appup/#{app_name}.appup"

      ebin_app_up_file =
        "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/ebin/#{app_name}.appup"

      if File.exists?(priv_app_up_file) do
        File.cp!(priv_app_up_file, ebin_app_up_file)
      end
    end

    add_version_to_rel_file = fn ->
      releases = "#{Storage.new_path(instance)}/releases"

      if File.exists?("#{releases}/#{app_name}.rel") do
        File.rename!("#{releases}/#{app_name}.rel", "#{releases}/#{app_name}-#{to_version}.rel")
      end
    end

    if app_lang == "erlang" do
      cp_appup_priv_to_ebin.()
      add_version_to_rel_file.()
    end

    with [file_path] <-
           Path.wildcard("#{Storage.new_path(instance)}/lib/#{app_name}-*/ebin/*.appup"),
         :ok <- check_app_up(file_path, from_version, to_version) do
      Logger.warning("HOT UPGRADE version DETECTED, from: #{from_version} to: #{to_version}")

      # Copy binary to the release folder under the version directory
      dest_dir = "#{Storage.current_path(instance)}/releases/#{to_version}"

      File.rm_rf(dest_dir)

      File.mkdir_p!(dest_dir)

      File.cp!(download_path, "#{dest_dir}/#{app_name}.tar.gz")

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

  @spec unpack_release(atom(), String.t(), charlist()) :: :ok | {:error, any()}
  def unpack_release(node, app_name, to_version) do
    release_link = "#{to_version}/#{app_name}" |> to_charlist

    case Rpc.call(node, :release_handler, :unpack_release, [release_link], @timeout) do
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

  @spec make_relup(atom(), integer(), String.t(), String.t(), charlist(), charlist()) ::
          :ok | {:error, :make_relup}
  def make_relup(node, instance, app_name, app_lang, from_version, to_version) do
    root = root_dir(node)

    cp_appup_priv_to_ebin = fn ->
      priv_app_up_file =
        "#{Storage.new_path(instance)}/lib/#{app_name}-#{to_version}/priv/appup/#{app_name}.appup"

      ebin_app_up_file =
        "#{Storage.current_path(instance)}/lib/#{app_name}-#{to_version}/ebin/#{app_name}.appup"

      if File.exists?(priv_app_up_file) do
        File.cp!(priv_app_up_file, ebin_app_up_file)
      end
    end

    add_version_to_rel_file = fn ->
      releases = "#{Storage.current_path(instance)}/releases"

      if File.exists?("#{releases}/#{app_name}.rel") do
        File.rename!("#{releases}/#{app_name}.rel", "#{releases}/#{app_name}-#{to_version}.rel")
      end
    end

    if app_lang == "erlang" do
      cp_appup_priv_to_ebin.()
      add_version_to_rel_file.()
    end

    Rpc.call(
      node,
      :systools,
      :make_relup,
      [
        root ++ ~c"/releases/#{app_name}-" ++ to_version,
        [root ++ ~c"/releases/#{app_name}-" ++ from_version],
        [root ++ ~c"/releases/#{app_name}-" ++ from_version],
        [
          {:path, [root ++ ~c"/lib/*/ebin"]},
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
    case Rpc.call(node, :release_handler, :check_install_release, [to_version], @timeout) do
      {:ok, _other, _desc} ->
        :ok

      {:error, reason} = result ->
        Logger.error("release_handler:check_install_release failed, reason: #{inspect(reason)}")
        result
    end
  end

  @spec install_release(atom(), charlist()) :: :ok | {:error, any()}
  def install_release(node, to_version) do
    case Rpc.call(
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

  @spec permfy(atom(), integer(), String.t(), String.t(), charlist()) :: :ok | {:error, any()}
  def permfy(node, instance, app_name, app_lang, to_version) do
    case Rpc.call(node, :release_handler, :make_permanent, [to_version], @timeout) do
      :ok ->
        Logger.info("Made release permanent: #{to_version}")

        if app_lang == "erlang" do
          File.cp!(
            "#{Storage.current_path(instance)}/bin/#{app_name}-#{to_version}",
            "#{Storage.current_path(instance)}/bin/#{app_name}"
          )
        end

        :ok

      reason ->
        Logger.error(
          "Error while trying to set a permanent version for #{to_version}, reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec root_dir(atom()) :: any()
  def root_dir(node), do: Rpc.call(node, :code, :root_dir, [], @timeout)

  @impl true
  @spec connect(integer()) :: {:error, :not_connecting} | {:ok, atom()}
  def connect(instance) do
    {:ok, hostname} = :inet.gethostname()
    app_sname = Storage.sname(instance)
    # NOTE: The command below represents the creation of an atom. However, with OTP distribution,
    #       all connected nodes share the same atoms, including its name.
    node = :"#{app_sname}@#{hostname}"

    case Node.connect(node) do
      true ->
        {:ok, node}

      reason ->
        Logger.error(
          "Error while trying to connect with node: #{inspect(node)} reason: #{inspect(reason)}"
        )

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
