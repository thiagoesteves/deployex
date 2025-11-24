defmodule Deployer.Upgrade.Application do
  @moduledoc """
  This module will provide functions to update the application based on the appup.

  For a hotupgrade to happen, a few steps need to be followed:
  1. Ensure that .appup files are available. These files are generated during the release process
     when updating from an older version. Deployer was designed to consume appup files generated
     by these libraries:
       a. [Jellyfish](https://github.com/thiagoesteves/jellyfish) (For Elixir apps)
       a. [Rebar3 appup plugin](https://github.com/lrascao/rebar3_appup_plugin) (For Erlang apps)

  2. During deployment, the release app-new-version.tar.gz is copied to a directory named
     after the version under the current/releases folder, for example:
     /var/lib/deployex/service/{myapp}/{sname}/current/releases/{new-version}/app-new-version.tar.gz

  3. A sequence of commands is executed by this module:
       a. Unpack a release using release_handler:unpack_release
       b. Create a relup file using systools:make_relup
       c. Check Install release using release_handler:check_install_release
         i. Request via RPC to run  ConfigProvider and Runtime and populate sys.config (Only ELixir)
       d. Install the release using release_handler:install_release
       e. Make the release permanent using release_handler:make_permanent
         i. Return original empty sys.config (Only ELixir)

    Note that only upgrades are permitted in this project, and in the event of
     failure, the system will revert to a full deployment.

  4. ATTENTION:
     The sys.config file contains all application configurations and is not loaded during a
     hot upgrade. For Elixir applications, Config Provider and Runtime are codes that executes
     when the application is starting and are required for fetching information.
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

  alias Foundation.Rpc

  @behaviour Deployer.Upgrade.Adapter
  @events_topic "deployex::hotupgrade::events"

  alias Deployer.Upgrade.Check
  alias Deployer.Upgrade.Execute

  require Logger

  ### ==========================================================================
  ### Public APIS
  ### ==========================================================================
  @impl true
  def subscribe_events, do: Phoenix.PubSub.subscribe(Deployer.PubSub, @events_topic)

  @impl true
  @spec execute(Execute.t()) :: :ok | {:error, any()}
  def execute(%Execute{from_version: from_version, to_version: to_version})
      when is_nil(from_version) or is_nil(to_version),
      do: {:error, :invalid_version}

  def execute(%Execute{from_version: from_version, to_version: to_version} = data)
      when is_binary(from_version) or is_binary(to_version) do
    execute(%{
      data
      | from_version: from_version |> to_charlist,
        to_version: to_version |> to_charlist
    })
  end

  def execute(%Execute{from_version: from_version, to_version: to_version} = data) do
    notify_progress(data.sname, "Starting upgrade for #{data.sname}...")

    with {:ok, node} <- connect(data.node),
         :ok <- notify_progress(data.sname, "Unpacking release"),
         :ok <- unpack_release(data),
         :ok <- notify_progress(data.sname, "Creating relup file"),
         :ok <- make_relup(data),
         :ok <- notify_progress(data.sname, "Checking release can be installed"),
         :ok <- check_install_release(data),
         :ok <- notify_progress(data.sname, "Updating sys.config file"),
         :ok <- update_sys_config_from_installed_version(data),
         :ok <- notify_progress(data.sname, "Installing release"),
         :ok <- install_release(data),
         :ok <- notify_progress(data.sname, "Returning original sys.config file"),
         :ok <- return_original_sys_config(data),
         :ok <- notify_make_permanent(data.skip_make_permanent, data.sname, data.to_version),
         :ok <- permfy(data),
         :ok <- notify_complete_ok(data.skip_make_permanent, data.sname) do
      message =
        "Release upgrade executed with success at node: #{node} from: #{from_version} to: #{to_version}"

      Logger.info(message)

      :ok
    else
      error ->
        notify_error(data.sname, error)
        error
    end
  end

  @spec which_releases(node()) :: list()
  def which_releases(node) do
    releases = Rpc.call(node, :release_handler, :which_releases, [], @timeout)

    releases |> Enum.map(fn {_name, version, _modules, status} -> {status, version} end)
  end

  @spec update_sys_config_from_installed_version(Execute.t()) :: :ok | {:error, any()}
  def update_sys_config_from_installed_version(%Execute{
        node: node,
        language: "elixir",
        current_path: current_path,
        to_version: to_version
      }) do
    rel_vsn_dir = "#{current_path}/releases/#{to_version}"
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

  def update_sys_config_from_installed_version(_data), do: :ok

  @spec return_original_sys_config(Execute.t()) :: :ok | {:error, any()}
  def return_original_sys_config(%Execute{
        language: "elixir",
        current_path: current_path,
        to_version: to_version
      }) do
    rel_vsn_dir = "#{current_path}/releases/#{to_version}"
    sys_config_path = "#{rel_vsn_dir}/sys.config"
    original_sys_config_file = "#{rel_vsn_dir}/original.sys.config"

    File.rename(original_sys_config_file, sys_config_path)
  end

  def return_original_sys_config(_data), do: :ok

  @impl true
  def prepare_new_path(name, "erlang", to_version, new_path) do
    priv_app_up_file =
      "#{new_path}/lib/#{name}-#{to_version}/priv/appup/#{name}.appup"

    ebin_app_up_file =
      "#{new_path}/lib/#{name}-#{to_version}/ebin/#{name}.appup"

    if File.exists?(priv_app_up_file) do
      File.cp(priv_app_up_file, ebin_app_up_file)
    end

    releases = "#{new_path}/releases"

    if File.exists?("#{releases}/#{name}.rel") do
      File.rename("#{releases}/#{name}.rel", "#{releases}/#{name}-#{to_version}.rel")
    end

    :ok
  end

  def prepare_new_path(_name, _language, _to_version, _new_path), do: :ok

  @impl true
  def check(%Check{from_version: from_version, to_version: to_version} = data)
      when is_binary(from_version) or is_binary(to_version) do
    check(%{
      data
      | from_version: from_version |> to_charlist,
        to_version: to_version |> to_charlist
    })
  end

  def check(%Check{
        name: name,
        language: "elixir",
        current_path: current_path,
        new_path: new_path,
        download_path: download_path,
        from_version: from_version,
        to_version: to_version
      }) do
    # NOTE: Single file for single elixir app or multiple files for umbrella
    jellyfish_files = Path.wildcard("#{new_path}/lib/*-*/ebin/jellyfish.json")

    case check_jellyfish_files(jellyfish_files, from_version, to_version) do
      {:ok, jellyfish_info} ->
        Logger.warning("HOT UPGRADE version DETECTED - #{inspect(jellyfish_info)}")

        # Copy binary to the release folder under the version directory
        dest_dir = "#{current_path}/releases/#{to_version}"

        File.rm_rf(dest_dir)

        File.mkdir_p!(dest_dir)

        File.cp!(download_path, "#{dest_dir}/#{name}.tar.gz")

        {:ok, :hot_upgrade}

      {:error, reason} ->
        Logger.warning(
          "HOT UPGRADE version NOT DETECTED, full deployment required, reason: #{inspect(reason)}"
        )

        {:ok, :full_deployment}
    end
  end

  def check(%Check{
        name: name,
        language: "erlang",
        current_path: current_path,
        new_path: new_path,
        download_path: download_path,
        from_version: from_version,
        to_version: to_version
      }) do
    with [file_path] <-
           Path.wildcard("#{new_path}/lib/#{name}-*/ebin/*.appup"),
         :ok <- check_app_up(file_path, from_version, to_version) do
      Logger.warning("HOT UPGRADE version DETECTED, from: #{from_version} to: #{to_version}")

      # Copy binary to the release folder under the version directory
      dest_dir = "#{current_path}/releases/#{to_version}"

      File.rm_rf(dest_dir)

      File.mkdir_p!(dest_dir)

      File.cp!(download_path, "#{dest_dir}/#{name}.tar.gz")

      {:ok, :hot_upgrade}
    else
      result ->
        Logger.warning(
          "HOT UPGRADE version NOT DETECTED, full deployment required, result: #{inspect(result)}"
        )

        {:ok, :full_deployment}
    end
  end

  def check(_data) do
    Logger.warning("HOT UPGRADE version NOT SUPPORTED, full deployment required")

    {:ok, :full_deployment}
  end

  defp check_jellyfish_files(files, from_version, to_version) do
    response =
      Enum.reduce_while(files, [], fn file, acc ->
        appup_info = file |> File.read!() |> Jason.decode!()
        dir = Path.dirname(file)

        with true <- "#{from_version}" == appup_info["from"],
             true <- "#{to_version}" == appup_info["to"],
             [appup] <- Path.wildcard("#{dir}/*.appup"),
             :ok <- check_app_up(appup, from_version, to_version) do
          {:cont, acc ++ [appup_info]}
        else
          {:error, reason} ->
            {:halt, {:error, reason}}

          false ->
            {:halt, {:error, :no_match_versions}}

          _ ->
            {:halt, []}
        end
      end)

    case response do
      [] ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}

      jellyfish_info ->
        {:ok, jellyfish_info}
    end
  end

  @spec check_app_up(binary(), charlist(), charlist()) ::
          :ok | {:error, :error_reading_file | :no_match_versions}
  def check_app_up(file_path, from_version, to_version) do
    match_version_upgrade? = fn list, from_version, to_version ->
      Enum.any?(list, fn
        {^to_version, [{^from_version, _}], [{^from_version, _}]} ->
          true

        _app_up ->
          false
      end)
    end

    with {:ok, app_up_list} <- :file.consult(file_path),
         true <- match_version_upgrade?.(app_up_list, from_version, to_version) do
      :ok
    else
      false ->
        {:error, :no_match_versions}

      reason ->
        Logger.error("Error while reading appup file, reason: #{inspect(reason)}")

        {:error, :error_reading_file}
    end
  end

  @spec unpack_release(Execute.t()) :: :ok | {:error, any()}
  def unpack_release(%Execute{node: node, name: name, to_version: to_version}) do
    release_link = "#{to_version}/#{name}" |> to_charlist

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

  @spec make_relup(Execute.t()) :: :ok | {:error, any()}
  def make_relup(%Execute{
        node: node,
        name: name,
        language: language,
        current_path: current_path,
        new_path: new_path,
        from_version: from_version,
        to_version: to_version
      }) do
    root = root_dir(node)

    cp_appup_priv_to_ebin = fn ->
      priv_app_up_file = "#{new_path}/lib/#{name}-#{to_version}/priv/appup/#{name}.appup"

      ebin_app_up_file = "#{current_path}/lib/#{name}-#{to_version}/ebin/#{name}.appup"

      if File.exists?(priv_app_up_file) do
        File.cp!(priv_app_up_file, ebin_app_up_file)
      end
    end

    add_version_to_rel_file = fn ->
      releases = "#{current_path}/releases"

      if File.exists?("#{releases}/#{name}.rel") do
        File.rename!("#{releases}/#{name}.rel", "#{releases}/#{name}-#{to_version}.rel")
      end
    end

    if language == "erlang" do
      cp_appup_priv_to_ebin.()
      add_version_to_rel_file.()
    end

    Rpc.call(
      node,
      :systools,
      :make_relup,
      [
        root ++ ~c"/releases/#{name}-" ++ to_version,
        [root ++ ~c"/releases/#{name}-" ++ from_version],
        [root ++ ~c"/releases/#{name}-" ++ from_version],
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

  @spec check_install_release(Execute.t()) :: :ok | {:error, any()}
  def check_install_release(%Execute{node: node, to_version: to_version}) do
    case Rpc.call(node, :release_handler, :check_install_release, [to_version], @timeout) do
      {:ok, _other, _desc} ->
        :ok

      {:error, reason} = result ->
        Logger.error("release_handler:check_install_release failed, reason: #{inspect(reason)}")
        result
    end
  end

  @spec install_release(Execute.t()) :: :ok | {:error, any()}
  def install_release(%Execute{node: node, to_version: to_version}) do
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

  @spec permfy(Execute.t()) :: :ok | {:error, any()}
  def permfy(%Execute{skip_make_permanent: true}) do
    # NOTE: Self-upgrade limitation - permify must be executed in a separate sequence.
    #       When DeployEx upgrades itself, including permify in the main upgrade sequence
    #       causes the process to crash after successfully applying the changes. This occurs
    #       when initiated via /bin/deployex rpc or iex. Tests with asynchronous tasks did
    #       not resolve this issue. The permify step succeeds, but the calling process is
    #       killed during the make_permanent operation.
    #
    #       This issue does not occur with managed applications because DeployEx calls each
    #       upgrade step individually from an external process. When upgrading itself, the
    #       calling process is part of the system being upgraded, causing it to be terminated
    #       when permify triggers supervisor restarts.
    #
    #       Solution: Split the upgrade into two sequences - complete the upgrade without
    #       permify, then call permify separately after the upgrade succeeds.
    :ok
  end

  def permfy(%Execute{
        node: node,
        name: name,
        language: language,
        current_path: current_path,
        to_version: to_version
      }) do
    case Rpc.call(node, :release_handler, :make_permanent, [to_version], @timeout) do
      :ok ->
        Logger.info("Made release permanent: #{to_version}")

        if language == "erlang" do
          File.cp!(
            "#{current_path}/bin/#{name}-#{to_version}",
            "#{current_path}/bin/#{name}"
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

  @spec root_dir(node()) :: any()
  def root_dir(node), do: Rpc.call(node, :code, :root_dir, [], @timeout)

  @impl true
  @spec connect(node()) :: {:error, :not_connecting} | {:ok, node()}
  def connect(node) do
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

  def notify_make_permanent(skip \\ false, sname, version)

  def notify_make_permanent(true, _sname, _version), do: :ok

  def notify_make_permanent(false, sname, version) do
    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_progress, Node.self(), sname, "Making release #{version} permanent"}
    )
  end

  def notify_progress(sname, msg) do
    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_progress, Node.self(), sname, msg}
    )
  end

  def notify_complete_ok(skip \\ false, sname)

  def notify_complete_ok(true, _sname), do: :ok

  def notify_complete_ok(_skip, sname) do
    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_complete, Node.self(), sname, :ok, "Hot upgrade applied successfully!"}
    )
  end

  def notify_error(sname, result) do
    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_complete, Node.self(), sname, :error, "Upgrade failed: #{inspect(result)}"}
    )
  end
end
