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
         i. Apply the resolved config to the running node (Only Elixir)
       e. Make the release permanent using release_handler:make_permanent

    Note that only upgrades are permitted in this project, and in the event of
     failure, the system will revert to a full deployment.

  4. ATTENTION:
     For Elixir applications, `runtime.exs` and the Config Providers only execute when the
     application boots, never during a hot upgrade. Worse, `release_handler` actively undoes
     their result: `change_appl_data/3` rebuilds the environment of EVERY loaded application
     from the build time sys.config, so everything `runtime.exs` produced is gone the moment
     the release is installed.

     This module therefore resolves that configuration itself, running the providers over the
     RPC channel, and applies it with `:application.set_env/2` - the primitive
     `Config.Provider` uses on a cold start through `Application.put_all_env/2`. Nothing is
     serialized on the way, which matters because a resolved configuration can hold values with
     no textual term syntax, such as the closure in
     `customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]`
     for an Ecto Repo. Writing one to sys.config prints it as `#Fun<...>`, and OTP does not
     report that: the file no longer parses, `change_appl_data/3` falls back to an empty config
     and every application silently reverts to its compile time environment.

     The configuration is applied twice, which is harmless and deliberate. A hook spliced into
     the relup (see `install_runtime_config_hook/2`) applies it from inside
     `install_release/2`, before any `suspend` or `code_change` observes the reset environment,
     and `apply_runtime_config/2` applies it again afterwards so the upgrade never depends on
     the hook being in place.

     Note that the providers execute within the current version, meaning the system is not
     immediately prepared to execute hot upgrades when configuration changes occur.

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
         :ok <- notify_progress(data.sname, "Resolving the runtime configuration"),
         {:ok, runtime_config} <- resolve_runtime_config(data),
         :ok <- install_runtime_config_hook(data, runtime_config),
         :ok <- notify_progress(data.sname, "Installing release"),
         :ok <- install_release(data),
         :ok <- notify_progress(data.sname, "Applying the runtime configuration"),
         :ok <- apply_runtime_config(data, runtime_config),
         :ok <- notify_make_permanent(data.make_permanent_async, data.sname, data.to_version),
         :ok <- permfy(data),
         :ok <- notify_complete_ok(data.make_permanent_async, data.sname) do
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

  @doc """
  Resolve the configuration of the version being installed.

  Reads the build time sys.config of the new version and runs its `runtime.exs` and Config
  Providers over RPC, producing exactly the configuration the application would have had on a
  cold boot. The file itself is only read, never written.
  """
  @spec resolve_runtime_config(Execute.t()) :: {:ok, runtime_config()} | {:error, any()}
  def resolve_runtime_config(%Execute{
        node: node,
        language: "elixir",
        current_path: current_path,
        to_version: to_version
      }) do
    sys_config_path = "#{current_path}/releases/#{to_version}/sys.config"

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
  Splice a hook into the generated relup that applies the resolved configuration from inside
  `release_handler:install_release/2`.

  `change_appl_data/3` rebuilds the environment of every application from the build time
  sys.config, and only then does `eval_script/5` run the relup instructions. An instruction at
  the head of the script therefore executes once the environment has been reset and before any
  `suspend`, `code_change` or `resume` can observe it.

  The configuration cannot travel in the relup, which `release_handler` also reads with
  `:file.consult/1`, and an anonymous function has no textual term syntax. It is stashed in
  `:persistent_term` over RPC instead, which survives `change_appl_data/3` because it is not
  application environment, and the relup carries only abstract forms, which are plain terms:

      {apply, {erl_eval, exprs, [Forms, []]}}

  evaluating `application:set_env(persistent_term:get(Key), [{persistent, true}])`. Nothing is
  compiled and no module is loaded into the target, so this does not depend on the OTP version
  the managed application was built with.

  This is an optimisation. When it fails the upgrade carries on and `apply_runtime_config/2`
  still applies the configuration once the release is installed.
  """
  @spec install_runtime_config_hook(Execute.t(), runtime_config()) :: :ok
  def install_runtime_config_hook(_data, []), do: :ok

  def install_runtime_config_hook(
        %Execute{node: node, current_path: current_path, to_version: to_version},
        runtime_config
      ) do
    relup_path = "#{current_path}/releases/#{to_version}/relup"

    with :ok <- stash_runtime_config(node, runtime_config),
         :ok <- splice_runtime_config_hook(relup_path) do
      Logger.info("Runtime config hook added to the relup at: #{relup_path}")
    else
      {:error, reason} ->
        Logger.warning(
          "Could not add the runtime config hook, reason: #{inspect(reason)}. The configuration " <>
            "is applied after the release is installed instead."
        )
    end

    :ok
  end

  @doc """
  Apply the resolved configuration to the running node.

  `release_handler:install_release/2` rebuilds the environment of every application from the
  build time sys.config, so the values produced by `runtime.exs` and the Config Providers have
  to be set again afterwards.

  `:application.set_env/2` is the primitive Elixir itself uses on a cold start:
  `Config.Provider.boot/1` calls `Application.put_all_env(config, persistent: true)`, a straight
  delegation to it, whenever the release does not reboot after config. Nothing is serialized, so
  values with no textual term syntax are carried without trouble.
  """
  @spec apply_runtime_config(Execute.t(), runtime_config()) :: :ok | {:error, any()}
  def apply_runtime_config(_data, []), do: :ok

  def apply_runtime_config(%Execute{node: node}, runtime_config) do
    case Rpc.call(
           node,
           :application,
           :set_env,
           [runtime_config, [persistent: true]],
           @rpc_timeout
         ) do
      :ok ->
        Logger.info("Applied runtime config for apps: #{inspect(Keyword.keys(runtime_config))}")

        # Setting the same values twice is harmless, the relup hook may already have applied
        # them, but the stash must not outlive the upgrade
        _ = Rpc.call(node, :persistent_term, :erase, [@runtime_config_key], @rpc_timeout)

        :ok

      reason ->
        Logger.error("Error while applying runtime config, reason: #{inspect(reason)}")

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

  # Run runtime.exs and the Config Providers for the version being installed. They execute over
  # RPC inside the still running old version, so a provider that assumes a cold system fails
  # here. Mirror Config.Provider.run_providers/2 and require a list back, otherwise the failure
  # reason would be carried forward as if it were the configuration.
  @spec run_config_providers(node(), keyword()) :: {:ok, runtime_config()} | {:error, any()}
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

  # An emulator upgrade restarts the VM and the configuration is resolved again on boot, so
  # there is nothing to apply and the script must keep restart_new_emulator at its head
  defp prepend_instruction({from_vsn, descr, [:restart_new_emulator | _] = script}, _instruction),
    do: {from_vsn, descr, script}

  defp prepend_instruction({from_vsn, descr, script}, instruction),
    do: {from_vsn, descr, [instruction | script]}

  # Abstract forms for:
  #   application:set_env(persistent_term:get(Key), [{persistent, true}])
  # Forms are plain terms, so unlike the configuration they survive the relup file, and
  # erl_eval is in stdlib so nothing has to be compiled or loaded into the target node.
  @spec runtime_config_hook_forms() :: [tuple()]
  defp runtime_config_hook_forms do
    l = 0
    {app, key} = @runtime_config_key

    [
      {:call, l, {:remote, l, {:atom, l, :application}, {:atom, l, :set_env}},
       [
         {:call, l, {:remote, l, {:atom, l, :persistent_term}, {:atom, l, :get}},
          [{:tuple, l, [{:atom, l, app}, {:atom, l, key}]}]},
         {:cons, l, {:tuple, l, [{:atom, l, :persistent}, {:atom, l, true}]}, {nil, l}}
       ]}
    ]
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
