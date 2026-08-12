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
         i. Request via RPC to run ConfigProvider and Runtime and resolve the config (Only Elixir)
         ii. Add a hook to the relup that applies that config during the install (Only Elixir)
       d. Install the release using release_handler:install_release
       e. Make the release permanent using release_handler:make_permanent

    Note that only upgrades are permitted in this project, and in the event of
     failure, the system will revert to a full deployment.

  4. ATTENTION:
     For Elixir applications, `runtime.exs` and the Config Providers only execute when the
     application boots, never during a hot upgrade. Worse, `release_handler` actively undoes
     their result: `change_appl_data/3` rebuilds the environment of EVERY loaded application
     from the build time sys.config, so everything `runtime.exs` produced is gone the moment
     the release is installed.

     This module therefore resolves that configuration itself over the RPC channel and applies
     it with `:application.set_env/2`, the primitive `Config.Provider` uses on a cold start
     through `Application.put_all_env/2`.

     Writing the resolved configuration back into sys.config, which is what this module used
     to do, only works for values `:file.consult/1` can read back. A resolved configuration can
     hold values with no textual term syntax, such as the closure in
     `customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]`
     for an Ecto Repo. That is printed as `#Fun<...>`, the file stops parsing, and OTP does not
     report it: `change_appl_data/3` falls back to an empty config and every application
     silently reverts to its compile time environment while the upgrade reports success.

     sys.config is now only read. The configuration is applied by a hook spliced into the relup
     (see `install_runtime_config_hook/2`), which runs inside `install_release/2` right after
     the environment has been reset and before any `suspend` or `code_change` observes it.

     What that means for a configuration change between versions:

     * A changed or removed key is picked up. `change_appl_data/3` calls `del_env/1` before
       `add_env/2`, rebuilding the environment of each application from the new `.app` file and
       the new build time sys.config, and `change_application_data/2` replaces `conf_data`
       rather than merging it. So a key deleted in the new version does not survive, not even
       through the `persistent: true` used here, and the hook only adds back what the new
       version actually resolves.

     * A changed `runtime.exs` is picked up, since the new version's sys.config points the
       `Config.Reader` provider at the new version's file, which `unpack_release/1` has already
       written to disk. It is evaluated by the code the running node has loaded, so it must not
       depend on modules or language features that only arrive with the new release.

     * A changed Config Provider is NOT picked up. The provider modules execute over RPC on the
       running node, which is still on the old version - `install_release/2` has not run yet.
       The old implementation is what resolves the configuration, so a fix to a provider only
       takes effect after a full deployment has made it the running version.

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
  @runtime_config_key {:deployex, :runtime_config}

  alias Deployer.HotUpgrade.Check
  alias Deployer.HotUpgrade.Execute
  alias Deployer.HotUpgrade.Jellyfish
  alias Foundation.Rpc

  @typedoc """
  The configuration produced by `runtime.exs` and the Config Providers of the version being
  installed. Same shape as sys.config itself: `[{app, [{key, value}]}]`.
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

        apply_after_async_make_permanent(params.after_async_make_permanent)

      reason ->
        notify_error(params.sname, reason)
    end

    {:noreply, state}
  end

  # The callback is an MFA rather than a function, and it is applied rather than called, so
  # it resolves to whatever version of the module is loaded now. install_release has already
  # swapped this release in by the time it runs, and a function captured by the previous
  # version raises BadFunctionError, killing this process with the work still undone
  defp apply_after_async_make_permanent(nil), do: :ok

  defp apply_after_async_make_permanent({module, function, args}) do
    apply(module, function, args)
  rescue
    error ->
      # The upgrade itself is finished and permanent at this point, whatever this was meant
      # to record must not undo that
      Logger.error(
        "Error while running the after make permanent callback, reason: #{inspect(error)}"
      )

      :ok
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

  def do_execute(%Execute{} = data) do
    notify_progress(data.sname, "Starting upgrade for #{data.sname}...")

    with {:ok, node} <- connect(data.node),
         :ok <- prepare_release(data) do
      install(data, node)
    else
      {:error, reason} = error ->
        report_failure(data, error)
        {:error, {:not_installed, reason}}
    end
  end

  # Everything here only writes files and builds the relup, the running node is never
  # touched. Failing at any of these steps leaves it running exactly the code it had, which
  # is what the caller is told through {:error, {:not_installed, reason}}
  defp prepare_release(%Execute{sname: sname} = data) do
    with :ok <- notify_progress(sname, "Unpacking release"),
         :ok <- unpack_release(data),
         :ok <- notify_progress(sname, "Creating relup file"),
         :ok <- make_relup(data),
         :ok <- notify_progress(sname, "Checking release can be installed"),
         :ok <- check_install_release(data),
         :ok <- notify_progress(sname, "Resolving the runtime configuration"),
         {:ok, runtime_config} <- resolve_runtime_config(data),
         :ok <- notify_progress(sname, "Adding the runtime configuration to the relup") do
      install_runtime_config_hook(data, runtime_config)
    end
  end

  # From install_release on the node is running the new code, so a failure has already
  # changed it and the previous version can no longer be assumed to be in place
  defp install(%Execute{from_version: from_version, to_version: to_version} = data, node) do
    with :ok <- notify_progress(data.sname, "Installing release"),
         :ok <- install_release(data),
         :ok <- notify_make_permanent(data.make_permanent_async, data.sname, data.to_version),
         :ok <- permfy(data),
         :ok <- notify_complete_ok(data.make_permanent_async, data.sname) do
      Logger.info(
        "Release upgrade executed with success at node: #{node} from: #{from_version} to: #{to_version}"
      )

      :ok
    else
      error ->
        report_failure(data, error)
        error
    end
  end

  defp report_failure(data, error) do
    # remove_unpacked_release/1 only acts while the release is still unpacked, so an error
    # after it was installed leaves it alone
    remove_unpacked_release(data)
    notify_error(data.sname, error)
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
          # NOTE: silent stops systools printing the reason to stdout, where it lands
          #       unprefixed and detached from the failure, and returns it instead. The
          #       relup file is still written, only noexec skips that
          :silent,
          {:path, [root ++ ~c"/lib/*/ebin"]},
          {:outdir, [root ++ ~c"/releases/" ++ to_version]}
        ]
      ],
      @rpc_timeout
    )
    |> case do
      {:ok, _relup, _module, []} ->
        :ok

      {:ok, _relup, module, warnings} ->
        Logger.warning("systools:make_relup warnings: #{format_systools(node, module, warnings)}")
        :ok

      {:error, module, error} ->
        Logger.error(
          "systools:make_relup failed for #{name} #{from_version} -> #{to_version}, " <>
            "reason: #{format_systools(node, module, error)}"
        )

        {:error, :make_relup}

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

  @doc """
  Remove a release that was unpacked but never installed.

  `release_handler:unpack_release/1` registers the release before the upgrade continues,
  so a failure anywhere after it leaves the version behind with status `unpacked`. The
  next attempt at the same version then fails with `{:existing_release, version}` before
  it starts, and the files sitting in the release directory are the ones from the attempt
  that failed, which may not be the ones the next attempt intends to install.

  Only a release still marked `unpacked` is unregistered. Once it is `current` or
  `permanent` the code is in use, and `release_handler` refuses to touch a permanent
  release anyway.

  `release_handler:set_removed/1` is used rather than `remove_release/1`. The latter also
  deletes every library the removed release brought that no *other* release in `RELEASES`
  declares, and an Elixir release ships no `RELEASES` file, so `release_handler` invents an
  entry for the running release with an empty library list. Every library would then look
  unused, including the ones the running release needs, and `lib/` would be emptied under a
  node that keeps working only until it is restarted. `set_removed/1` unregisters the
  version and leaves the files alone, which is all that is needed for the version to be
  applied again.
  """
  @spec remove_unpacked_release(Execute.t()) :: :ok
  def remove_unpacked_release(%Execute{node: node, to_version: to_version}) do
    version = to_charlist(to_version)

    case List.keyfind(which_releases(node), version, 1) do
      {:unpacked, ^version} ->
        case Rpc.call(node, :release_handler, :set_removed, [version], @rpc_timeout) do
          :ok ->
            Logger.info(
              "Unregistered the unpacked release #{to_version} left by the failed upgrade, " <>
                "the version can be applied again"
            )

          reason ->
            Logger.error(
              "Error while removing the unpacked release #{to_version}, reason: #{inspect(reason)}"
            )
        end

      _ ->
        # Either never unpacked, or already installed and in use
        :ok
    end

    :ok
  end

  @spec which_releases(node()) :: list()
  def which_releases(node) do
    releases = Rpc.call(node, :release_handler, :which_releases, [], @rpc_timeout)

    releases |> Enum.map(fn {_name, version, _modules, status} -> {status, version} end)
  end

  @doc """
  Resolve the configuration of the version being installed.

  Reads the build time sys.config of the new version and runs its `runtime.exs` and Config
  Providers over RPC, producing exactly the configuration the application would have had on a
  cold boot. The file is only read, never written.
  """
  @spec resolve_runtime_config(Execute.t()) :: {:ok, runtime_config()} | {:error, any()}
  def resolve_runtime_config(%Execute{
        node: node,
        language: "elixir",
        current_path: current_path,
        to_version: to_version
      }) do
    sys_config_path = "#{current_path}/releases/#{to_version}/sys.config"

    # Read the build time config, then run runtime.exs and the Config Providers on top of it
    case :file.consult(sys_config_path) do
      {:ok, [sys_config]} ->
        run_config_providers(node, sys_config)

      reason ->
        Logger.error("Error while reading #{sys_config_path}, reason: #{inspect(reason)}")

        {:error, {:unreadable_sys_config, reason}}
    end
  end

  def resolve_runtime_config(_data), do: {:ok, []}

  @doc """
  Add a hook to the generated relup that applies the resolved configuration from inside
  `release_handler:install_release/2`.

  The configuration used to be written back into sys.config, but that only works for values
  `:file.consult/1` can read back. An anonymous function has no textual term syntax and is
  printed as `#Fun<...>`, which OTP does not report: the file stops parsing,
  `change_appl_data/3` falls back to an empty config and every application silently reverts to
  its compile time environment.

  `change_appl_data/3` rebuilds that environment before `eval_script/5` runs the relup, so an
  instruction at the head of the script executes once the environment has been reset and
  before any `suspend`, `code_change` or `resume` can observe it.

  The configuration cannot travel in the relup either, which `release_handler` also reads with
  `:file.consult/1`. It is stashed in `:persistent_term` over RPC, which survives
  `change_appl_data/3` because it is not application environment, and the relup carries only
  abstract forms, which are plain terms:

      {apply, {erl_eval, exprs, [Forms, []]}}

  evaluating `application:set_env(persistent_term:get(Key), [{persistent, true}])`. That is the
  primitive `Config.Provider` uses on a cold start through `Application.put_all_env/2`, and
  nothing is serialized on the way. No module is compiled or loaded into the target, so this
  does not depend on the OTP version the managed application was built with.
  """
  @spec install_runtime_config_hook(Execute.t(), runtime_config()) :: :ok | {:error, any()}
  def install_runtime_config_hook(_data, []), do: :ok

  def install_runtime_config_hook(
        %Execute{node: node, current_path: current_path, to_version: to_version},
        runtime_config
      ) do
    relup_path = "#{current_path}/releases/#{to_version}/relup"

    with :ok <- stash_runtime_config(node, runtime_config),
         :ok <- splice_runtime_config_hook(relup_path) do
      Logger.info("Runtime config hook added to the relup at: #{relup_path}")

      :ok
    else
      {:error, reason} ->
        # Installing without the hook would reset every application to its compile time
        # environment, so fail here and let the engine run a full deployment instead
        Logger.error(
          "Error while adding the runtime config hook to: #{relup_path}, reason: #{inspect(reason)}"
        )

        # Nothing will consume the stash now, and it holds whatever the Config Providers
        # produced, secrets included
        _ = Rpc.call(node, :persistent_term, :erase, [@runtime_config_key], @rpc_timeout)

        {:error, reason}
    end
  end

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

  @spec stash_runtime_config(node(), runtime_config()) :: :ok | {:error, any()}
  defp stash_runtime_config(node, runtime_config) do
    case Rpc.call(
           node,
           :persistent_term,
           :put,
           [@runtime_config_key, runtime_config],
           @rpc_timeout
         ) do
      :ok -> :ok
      reason -> {:error, {:stash_failed, reason}}
    end
  end

  @spec splice_runtime_config_hook(binary()) :: :ok | {:error, any()}
  defp splice_runtime_config_hook(relup_path) do
    instruction = {:apply, {:erl_eval, :exprs, [runtime_config_hook_forms(), []]}}

    case :file.consult(relup_path) do
      {:ok, [{to_vsn, up, down}]} ->
        patched = {to_vsn, Enum.map(up, &prepend_instruction(&1, instruction)), down}
        File.write(relup_path, :io_lib.format(~c"%% coding: utf-8~n~tp.~n", [patched]))

      reason ->
        {:error, {:unreadable_relup, reason}}
    end
  end

  # An emulator upgrade restarts the VM, which resolves the configuration again on boot, so
  # there is nothing to apply and the script must keep restart_new_emulator at its head
  defp prepend_instruction({from_vsn, descr, [:restart_new_emulator | _] = script}, _instruction),
    do: {from_vsn, descr, script}

  defp prepend_instruction({from_vsn, descr, script}, instruction),
    do: {from_vsn, descr, [instruction | script]}

  # Abstract forms for:
  #   application:set_env(persistent_term:get(Key), [{persistent, true}]),
  #   persistent_term:erase(Key)
  #
  # Forms are plain terms, so unlike the configuration they survive the relup file, and
  # erl_eval is in stdlib so nothing has to be compiled or loaded into the target node.
  #
  # The hook erases its own stash as its last act. The resolved configuration holds whatever
  # the Config Providers produced, secrets included, so it must not outlive the upgrade that
  # needed it.
  @spec runtime_config_hook_forms() :: [tuple()]
  defp runtime_config_hook_forms do
    l = 0

    key_form =
      {:tuple, l,
       [{:atom, l, elem(@runtime_config_key, 0)}, {:atom, l, elem(@runtime_config_key, 1)}]}

    [
      {:call, l, {:remote, l, {:atom, l, :application}, {:atom, l, :set_env}},
       [
         {:call, l, {:remote, l, {:atom, l, :persistent_term}, {:atom, l, :get}}, [key_form]},
         {:cons, l, {:tuple, l, [{:atom, l, :persistent}, {:atom, l, true}]}, {nil, l}}
       ]},
      {:call, l, {:remote, l, {:atom, l, :persistent_term}, {:atom, l, :erase}}, [key_form]}
    ]
  end

  # Run runtime.exs and the Config Providers for the version being installed.
  #
  # They execute over RPC inside the still running old version, so a provider that assumes a
  # cold system fails here: one that starts a process the application already owns comes back
  # as {:badrpc, {:EXIT, {{:badmatch, {:error, {:already_started, pid}}}, _}}} even though it
  # works on boot. Mirror Config.Provider.run_providers/2 and require a list back, otherwise
  # the failure reason is carried forward as if it were the configuration and ends up written
  # into sys.config.
  @spec run_config_providers(node(), keyword()) :: {:ok, keyword()} | {:error, any()}
  defp run_config_providers(node, sys_config) do
    sys_config
    |> Keyword.get(:elixir)
    |> Keyword.get(:config_provider_init)
    |> Map.get(:providers)
    |> Enum.reduce_while({:ok, sys_config}, fn {mod, arg}, {:ok, config} ->
      case Rpc.call(node, mod, :load, [config, arg], @rpc_timeout) do
        new_config when is_list(new_config) ->
          {:cont, {:ok, new_config}}

        reason ->
          Logger.error("""
          Config provider #{inspect(mod)} did not return a configuration on node #{node}, got: \
          #{inspect(reason)}. Providers run inside the already running old version, so they must \
          tolerate a started system: one that starts a process the application already owns fails \
          here with {:already_started, pid} even though it works on a cold boot.\
          """)

          {:halt, {:error, {:config_provider_failed, mod, reason}}}
      end
    end)
  end

  # systools reports through format_error/1 on the module it returns, which turns a term
  # such as {file_problem, {File, {open, enoent}}} into the sentence it would have printed
  defp format_systools(node, module, term) do
    case Rpc.call(node, module, :format_error, [term], @rpc_timeout) do
      formatted when is_list(formatted) or is_binary(formatted) ->
        formatted |> IO.chardata_to_string() |> String.trim()

      _ ->
        inspect(term)
    end
  rescue
    _ -> inspect(term)
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
