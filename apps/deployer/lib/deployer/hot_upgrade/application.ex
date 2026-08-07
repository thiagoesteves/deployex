defmodule Deployer.HotUpgrade.Application do
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
         i. Apply the config entries sys.config cannot carry (Only Elixir)
       e. Make the release permanent using release_handler:make_permanent
         i. Return original empty sys.config (Only ELixir)

    Note that only upgrades are permitted in this project, and in the event of
     failure, the system will revert to a full deployment.

  4. ATTENTION:
     The sys.config file contains all application configurations and is not loaded during a
     hot HotUpgrade. For Elixir applications, Config Provider and Runtime are codes that executes
     when the application is starting and are required for fetching information.
     To address this, several steps are included in this module to load the new
     version of sys.config and utilize the RPC channel to execute runtime.exs and the config
     provider. It's important to note that these actions occur within the current version,
     meaning the system is not immediately prepared to execute hot upgrades when configuration
     changes occur.

     sys.config can only hold terms that `:file.consult/1` can read back. A value with no
     textual term syntax - an anonymous function (for example
     `customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]`
     in an Ecto Repo), a pid, a port or a reference - is printed as `#Fun<...>` and makes the
     whole file unparseable. OTP does not report that: `release_handler:change_appl_data/3`
     falls back to an empty config and `change_application_data/2` then resets every
     application to its compile time environment, so the upgrade reports success while the
     runtime configuration is gone.

     Note that `fun M:F/A` does parse, but only names exported functions. A closure such as the
     one above is a compiler generated local lambda, so writing it that way yields a fun that
     raises `undef` when called - a worse failure than losing the configuration.

     Those entries are therefore kept out of the generated file, per `{app, key}` pair, and
     applied over RPC with `:application.set_env/2` right after the release is installed. That
     is the same primitive `Config.Provider` uses on a cold start through
     `Application.put_all_env/2`, which has no serialization step and carries these values
     without trouble. The generated file is then consulted back as a second guard, so anything
     the split does not catch fails the upgrade instead of silently wiping the configuration.

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

  use GenServer
  require Logger

  @rpc_timeout 60_000
  @execute_timeout 300_000
  @check_timeout 300_000
  @behaviour Deployer.HotUpgrade.Adapter
  @events_topic "deployex::hotupgrade::events"

  alias Deployer.HotUpgrade.Check
  alias Deployer.HotUpgrade.Execute
  alias Deployer.HotUpgrade.Jellyfish
  alias Foundation.Rpc

  @typedoc """
  Application environment entries that sys.config cannot carry, applied over RPC once the
  release is installed. Same shape as sys.config itself: `[{app, [{key, value}]}]`.
  """
  @type runtime_config :: [{app :: atom(), env :: keyword()}]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl GenServer
  def init(_args) do
    Logger.info("Initializing HotUpgrade server")

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:check, params}, _from, state) do
    response = do_check(params)
    {:reply, response, state}
  end

  def handle_call({:execute, params}, _from, state) do
    response = do_execute(params)
    {:reply, response, state}
  end

  @impl GenServer
  def handle_cast({:execute, params}, state) do
    do_execute(params)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:make_permanent, params}, state) do
    case permfy(%{params | make_permanent_async: false}) do
      :ok ->
        notify_complete_ok(params.sname)

        if params.after_async_make_permanent do
          params.after_async_make_permanent.()
        end

      reason ->
        notify_error(params.sname, reason)
    end

    {:noreply, state}
  end

  # NOTE: One possible improvement for these functions is to use a
  #       decremental timeout, where the timeout value is updated
  #       progressively. Once it reaches @execute_timeout, it should
  #       raise a timeout error instead of triggering multiple timeouts.
  @impl Deployer.HotUpgrade.Adapter
  def execute(%Execute{sync_execution: true} = params) do
    GenServer.call(__MODULE__, {:execute, params}, @execute_timeout)
  end

  def execute(%Execute{sync_execution: false} = params) do
    GenServer.cast(__MODULE__, {:execute, params})
  end

  @impl Deployer.HotUpgrade.Adapter
  def check(%Check{} = params) do
    GenServer.call(__MODULE__, {:check, params}, @check_timeout)
  end

  ### ==========================================================================
  ### Private and serialized functions
  ### ==========================================================================

  def do_execute(%Execute{from_version: from_version, to_version: to_version})
      when is_nil(from_version) or is_nil(to_version),
      do: {:error, :invalid_version}

  def do_execute(%Execute{from_version: from_version, to_version: to_version} = data)
      when is_binary(from_version) or is_binary(to_version) do
    do_execute(%{
      data
      | from_version: from_version |> to_charlist,
        to_version: to_version |> to_charlist
    })
  end

  def do_execute(%Execute{from_version: from_version, to_version: to_version} = data) do
    notify_progress(data.sname, "Starting upgrade for #{data.sname}...")

    with {:ok, node} <- connect(data.node),
         :ok <- notify_progress(data.sname, "Unpacking release"),
         :ok <- unpack_release(data),
         :ok <- notify_progress(data.sname, "Creating relup file"),
         :ok <- make_relup(data),
         :ok <- notify_progress(data.sname, "Checking release can be installed"),
         :ok <- check_install_release(data),
         :ok <- notify_progress(data.sname, "Updating sys.config file"),
         {:ok, runtime_config} <- update_sys_config_from_installed_version(data),
         :ok <- notify_progress(data.sname, "Installing release"),
         :ok <- install_release(data),
         :ok <- notify_progress(data.sname, "Applying the runtime configuration"),
         :ok <- restore_runtime_config(data, runtime_config),
         :ok <- notify_progress(data.sname, "Returning original sys.config file"),
         :ok <- return_original_sys_config(data),
         :ok <- notify_make_permanent(data.make_permanent_async, data.sname, data.to_version),
         :ok <- permfy(data),
         :ok <- notify_complete_ok(data.make_permanent_async, data.sname) do
      message =
        "Release upgrade executed with success at node: #{node} from: #{from_version} to: #{to_version}"

      Logger.info(message)

      :ok
    else
      error ->
        # A failure between the sys.config rewrite and install_release leaves the generated
        # file behind, and the next attempt reads it with :file.consult/1
        _ = return_original_sys_config(data)

        notify_error(data.sname, error)
        error
    end
  end

  def do_check(%Check{from_version: from_version, to_version: to_version} = data)
      when is_binary(from_version) or is_binary(to_version) do
    do_check(%{
      data
      | from_version: from_version |> to_charlist,
        to_version: to_version |> to_charlist
    })
  end

  def do_check(
        %Check{
          name: name,
          language: "elixir",
          current_path: current_path,
          new_path: new_path,
          download_path: download_path,
          from_version: from_version,
          to_version: to_version
        } = check
      ) do
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

        {:ok, %{check | deploy: :hot_upgrade, jellyfish_info: jellyfish_info}}

      {:error, reason} ->
        Logger.warning(
          "HOT UPGRADE version NOT DETECTED, full deployment required, reason: #{inspect(reason)}"
        )

        {:ok, %{check | deploy: :full_deployment}}
    end
  end

  def do_check(
        %Check{
          name: name,
          language: "erlang",
          current_path: current_path,
          new_path: new_path,
          download_path: download_path,
          from_version: from_version,
          to_version: to_version
        } = check
      ) do
    with [file_path] <-
           Path.wildcard("#{new_path}/lib/#{name}-*/ebin/*.appup"),
         :ok <- check_app_up(file_path, from_version, to_version) do
      Logger.warning("HOT UPGRADE version DETECTED, from: #{from_version} to: #{to_version}")

      # Copy binary to the release folder under the version directory
      dest_dir = "#{current_path}/releases/#{to_version}"

      File.rm_rf(dest_dir)

      File.mkdir_p!(dest_dir)

      File.cp!(download_path, "#{dest_dir}/#{name}.tar.gz")

      {:ok, %{check | deploy: :hot_upgrade}}
    else
      result ->
        Logger.warning(
          "HOT UPGRADE version NOT DETECTED, full deployment required, result: #{inspect(result)}"
        )

        {:ok, %{check | deploy: :full_deployment}}
    end
  end

  def do_check(check) do
    Logger.warning("HOT UPGRADE version NOT SUPPORTED, full deployment required")

    {:ok, %{check | deploy: :full_deployment}}
  end

  ### ==========================================================================
  ### Callbacks implementation
  ### ==========================================================================

  @impl Deployer.HotUpgrade.Adapter
  def subscribe_events, do: Phoenix.PubSub.subscribe(Deployer.PubSub, @events_topic)

  @impl Deployer.HotUpgrade.Adapter
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

  @impl Deployer.HotUpgrade.Adapter
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

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

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

    case Rpc.call(node, :release_handler, :unpack_release, [release_link], @rpc_timeout) do
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
      @rpc_timeout
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
    case Rpc.call(node, :release_handler, :check_install_release, [to_version], @rpc_timeout) do
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
           @rpc_timeout
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
  def permfy(%Execute{make_permanent_async: true} = params) do
    # NOTE: Self-upgrade limitation - permify must be executed in a separate sequence.
    #       When DeployEx upgrades itself, including permify in the main upgrade sequence
    #       causes the process to crash after successfully applying the changes. This occurs
    #       because the module itself was updated after the installation. The solution for this
    #       case is to run an async message, so when the module is called again, it will use
    #       the uploaded file
    #
    #       This issue does not occur with managed applications because DeployEx calls each
    #       upgrade step individually from an external process. When upgrading itself, the
    #       calling process is part of the system being upgraded, causing it to be terminated
    #       when permify triggers supervisor restarts.
    send(self(), {:make_permanent, params})
    :ok
  end

  def permfy(%Execute{
        node: node,
        name: name,
        language: language,
        current_path: current_path,
        to_version: to_version
      }) do
    case Rpc.call(node, :release_handler, :make_permanent, [to_version], @rpc_timeout) do
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

  @spec which_releases(node()) :: list()
  def which_releases(node) do
    releases = Rpc.call(node, :release_handler, :which_releases, [], @rpc_timeout)

    releases |> Enum.map(fn {_name, version, _modules, status} -> {status, version} end)
  end

  @spec update_sys_config_from_installed_version(Execute.t()) ::
          {:ok, runtime_config()} | {:error, any()}
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
        Rpc.call(node, mod, :load, [cfg, arg], @rpc_timeout)
      end)

    {serializable_config, runtime_config} = split_runtime_only_config(sys_config)

    log_deferred_config(runtime_config, to_version)

    with :ok <- File.rename(sys_config_path, original_sys_config_file),
         :ok <-
           File.write(
             sys_config_path,
             :io_lib.format(~c"%% coding: utf-8~n~tp.~n", [serializable_config])
           ),
         :ok <- validate_sys_config(sys_config_path) do
      {:ok, runtime_config}
    else
      {:error, reason} ->
        Logger.error(
          "Error while updating sys.config to: #{to_version}, reason: #{inspect(reason)}"
        )

        # Leave the release directory exactly as it was found. A generated sys.config left
        # behind is read by the next attempt with :file.consult/1, which would fail to match
        _ = File.rename(original_sys_config_file, sys_config_path)

        {:error, reason}
    end
  end

  def update_sys_config_from_installed_version(_data), do: {:ok, []}

  @doc """
  Apply the configuration entries that sys.config cannot carry.

  `release_handler:install_release/2` rebuilds the environment of every application from
  sys.config, so the entries held back by `update_sys_config_from_installed_version/1` only
  reach the running system once they are set again over RPC.
  """
  @spec restore_runtime_config(Execute.t(), runtime_config()) :: :ok | {:error, any()}
  def restore_runtime_config(_data, []), do: :ok

  def restore_runtime_config(%Execute{node: node}, runtime_config) do
    # NOTE: :application.set_env/2 is the primitive Elixir itself uses to apply the resolved
    #       runtime configuration on a cold start - Config.Provider.boot/1 calls
    #       Application.put_all_env(config, persistent: true), a straight delegation to it,
    #       whenever the release does not reboot after config. The whole configuration goes
    #       in a single call, in sys.config shape, so these entries land exactly as they
    #       would have on a normal boot.
    case Rpc.call(
           node,
           :application,
           :set_env,
           [runtime_config, [persistent: true]],
           @rpc_timeout
         ) do
      :ok ->
        Logger.info("Applied runtime config for apps: #{inspect(Keyword.keys(runtime_config))}")
        :ok

      reason ->
        Logger.error("Error while applying runtime config, reason: #{inspect(reason)}")

        {:error, reason}
    end
  end

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

  @spec root_dir(node :: node()) :: any()
  def root_dir(node), do: Rpc.call(node, :code, :root_dir, [], @rpc_timeout)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  @spec notify_make_permanent(skip :: boolean(), sname :: String.t(), version :: String.t()) ::
          :ok
  defp notify_make_permanent(true, _sname, _version), do: :ok

  defp notify_make_permanent(false, sname, version) do
    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_progress, Node.self(), sname, "Making release #{version} permanent"}
    )
  end

  @spec notify_progress(sname :: String.t(), msg :: String.t()) :: :ok
  defp notify_progress(sname, msg) do
    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_progress, Node.self(), sname, msg}
    )
  end

  @spec notify_complete_ok(skip :: boolean(), sname :: String.t()) :: :ok
  defp notify_complete_ok(skip \\ false, sname)

  defp notify_complete_ok(true, _sname), do: :ok

  defp notify_complete_ok(_skip, sname) do
    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_complete, Node.self(), sname, :ok, "Hot upgrade applied successfully!"}
    )

    Foundation.Notifications.notify("deployment_complete", %{
      node: node(),
      sname: sname,
      status: :ok,
      message: "Hot upgrade applied successfully!"
    })
  end

  @spec notify_error(sname :: String.t(), result :: any()) :: :ok
  defp notify_error(sname, result) do
    message = "Upgrade failed: #{inspect(result)}"

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @events_topic,
      {:hot_upgrade_complete, Node.self(), sname, :error, message}
    )

    Foundation.Notifications.notify("deployment_complete", %{
      node: node(),
      sname: sname,
      status: :error,
      message: message
    })
  end

  # Split the resolved config into the part sys.config can carry and the part that has to be
  # applied over RPC. The split is per {app, key} pair, never inside a value: a half written
  # entry is more dangerous than a missing one, since a Repo that keeps its url but loses its
  # ssl_opts would connect in plaintext rather than fail.
  @spec split_runtime_only_config(keyword()) :: {keyword(), runtime_config()}
  defp split_runtime_only_config(sys_config) do
    Enum.map_reduce(sys_config, [], fn
      {app, env}, acc when is_list(env) ->
        case Enum.split_with(env, fn
               {_key, value} -> sys_config_term?(value)
               _entry -> true
             end) do
          {keep, []} -> {{app, keep}, acc}
          {keep, defer} -> {{app, keep}, acc ++ [{app, defer}]}
        end

      entry, acc ->
        {entry, acc}
    end)
  end

  @spec log_deferred_config(runtime_config(), charlist() | binary()) :: :ok
  defp log_deferred_config([], _to_version), do: :ok

  defp log_deferred_config(runtime_config, to_version) do
    keys = for {app, env} <- runtime_config, {key, _value} <- env, do: {app, key}

    Logger.warning("""
    Hot upgrade to #{to_version}: #{inspect(keys)} hold values with no textual term syntax \
    (anonymous functions, pids, ports or references), so they cannot be written to sys.config \
    and are applied over RPC once the release is installed. They are absent from the \
    application environment while install_release/2 runs.\
    """)
  end

  # A term survives the :io_lib.format/2 + :file.consult/1 round trip only if it has no
  # function, pid, port or reference anywhere in it - those have no textual term syntax.
  @spec sys_config_term?(any()) :: boolean()
  defp sys_config_term?(value)
       when is_function(value) or is_pid(value) or is_port(value) or is_reference(value),
       do: false

  defp sys_config_term?([head | tail]), do: sys_config_term?(head) and sys_config_term?(tail)

  defp sys_config_term?(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> sys_config_term?()

  defp sys_config_term?(value) when is_map(value),
    do: value |> Map.to_list() |> sys_config_term?()

  defp sys_config_term?(_value), do: true

  # Read the file back the same way release_handler does, so a config that OTP would
  # silently discard fails the upgrade here instead of booting with a wiped environment.
  @spec validate_sys_config(binary()) :: :ok | {:error, any()}
  defp validate_sys_config(sys_config_path) do
    case :file.consult(sys_config_path) do
      {:ok, [_config]} -> :ok
      reason -> {:error, {:unparseable_sys_config, reason}}
    end
  end

  defp check_jellyfish_files(files, from_version, to_version) do
    response =
      Enum.reduce_while(files, [], fn file, acc ->
        appup_info = Jellyfish.decode_jellyfish_file(file)
        dir = Path.dirname(file)

        # Determine version validation strategy based on upgrade type
        # For project upgrades, use the provided versions
        # For dependency upgrades, use versions from metadata (dependencies have
        # independent versioning from the main project)
        {from, to} =
          case appup_info.type do
            "dependency" ->
              {to_charlist(appup_info.from), to_charlist(appup_info.to)}

            _ ->
              {from_version, to_version}
          end

        with true <- "#{from}" == appup_info.from,
             true <- "#{to}" == appup_info.to,
             [appup] <- Path.wildcard("#{dir}/*.appup"),
             :ok <- check_app_up(appup, from, to) do
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
end
