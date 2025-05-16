defmodule Foundation.Catalog.Local do
  @moduledoc """
  This module handles the storage information using local files and ets tables
  for temporary data
  """

  use GenServer

  alias Foundation.Common

  @behaviour Foundation.Catalog.Adapter

  require Logger

  @token_table :tokens
  @deployex_sname "deployex"
  @nohost_sname "nonode"
  @config_key_file "config.term"

  ### ==========================================================================
  ### GenServer callback functions
  ### ==========================================================================

  def start_link(_attrs) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_attrs) do
    :ets.new(@token_table, [:set, :protected, :named_table])

    setup()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:add_token, user_token}, _from, state) do
    :ets.insert(@token_table, {user_token.token, user_token})

    {:reply, :ok, state}
  end

  @impl true
  def add_user_session_token(user_token) do
    Common.call_gen_server(__MODULE__, {:add_token, user_token})
  end

  @impl true
  def get_user_session_token_by_token(token) do
    case :ets.lookup(@token_table, token) do
      [{_, value}] -> value
      _ -> nil
    end
  end

  ### ==========================================================================
  ### Foundation.Catalog.Adapter callback functions
  ### ==========================================================================

  @impl true
  def setup do
    # Create paths to store persistent information
    File.mkdir_p!(config_path())
    File.mkdir_p!(history_version_path())
    File.mkdir_p!(ghosted_version_path())

    # Cleanup deployments
    service_path = service_path("")
    Logger.info("Cleaning up deployments at: #{service_path}")
    File.rm_rf("#{service_path}")

    :ok
  end

  @impl true
  def setup(node) do
    case node_info(node) do
      %Foundation.Catalog.Node{name_string: app_name} ->
        [new_path(node), current_path(node), previous_path(node)]
        |> Enum.each(&File.mkdir_p!/1)

        File.mkdir_p!("#{log_path()}/#{app_name}")
        File.touch(stdout_path(node))
        File.touch(stderr_path(node))

        :ok

      nil ->
        Logger.error("Setup failed due to invalid node format: #{node}")
        {:error, :invalid_node}
    end
  end

  @impl true
  def cleanup(nil), do: :ok

  def cleanup(node) do
    case node_info(node) do
      %Foundation.Catalog.Node{sname: sname, name_string: name} ->
        File.rm_rf("#{service_path(name)}/#{sname}")
        :ok

      nil ->
        Logger.error("Cleanup failed due to invalid node format: #{node}")
        {:error, :invalid_node}
    end
  end

  @impl true
  def replicas, do: Application.get_env(:foundation, :replicas)

  @impl true
  def replicas_list, do: Enum.to_list(1..replicas())

  @impl true
  def monitored_app_name, do: Application.fetch_env!(:foundation, :monitored_app_name)

  @impl true
  def monitored_app_lang, do: Application.fetch_env!(:foundation, :monitored_app_lang)

  @impl true
  def monitored_app_env, do: Application.fetch_env!(:foundation, :monitored_app_env)

  @impl true
  def monitored_app_start_port, do: Application.get_env(:foundation, :monitored_app_start_port)

  @impl true
  def node_info(node) when is_atom(node) do
    node |> Atom.to_string() |> node_info()
  end

  def node_info(node) do
    case String.split(node, ["@"]) do
      [sname, hostname] ->
        case String.split(sname, ["-"]) do
          [name, suffix] ->
            %Foundation.Catalog.Node{
              node: String.to_existing_atom(node),
              sname: sname,
              name_string: name,
              name_atom: String.to_atom(name),
              hostname: hostname,
              suffix: suffix,
              # NOTE: Leave the next call with __MODULE__ until multiple apps are implemented
              #       It is used for testing purpose
              language: __MODULE__.monitored_app_lang()
            }

          [name] when name in [@deployex_sname, @nohost_sname] ->
            %Foundation.Catalog.Node{
              node: String.to_existing_atom(node),
              sname: @deployex_sname,
              name_string: @deployex_sname,
              name_atom: :deployex,
              hostname: hostname,
              suffix: ""
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @impl true
  def node_info_from_sname(sname) do
    {:ok, hostname} = :inet.gethostname()

    "#{sname}@#{hostname}" |> String.to_atom() |> node_info()
  end

  @impl true
  def stdout_path(node) do
    case node_info(node) do
      %Foundation.Catalog.Node{sname: @deployex_sname} ->
        log_path = Application.fetch_env!(:foundation, :log_path)
        "#{log_path}/deployex-stdout.log"

      %Foundation.Catalog.Node{sname: sname, name_string: name} ->
        log_path = Application.fetch_env!(:foundation, :monitored_app_log_path)
        "#{log_path}/#{name}/#{sname}-stdout.log"

      _ ->
        Logger.error("Stdout path failed due to invalid node format: #{node}")
        nil
    end
  end

  @impl true
  def stderr_path(node) do
    case node_info(node) do
      %Foundation.Catalog.Node{sname: @deployex_sname} ->
        log_path = Application.fetch_env!(:foundation, :log_path)
        "#{log_path}/deployex-stderr.log"

      %Foundation.Catalog.Node{sname: sname, name_string: name} ->
        log_path = Application.fetch_env!(:foundation, :monitored_app_log_path)
        "#{log_path}/#{name}/#{sname}-stderr.log"

      _ ->
        Logger.error("Stderr path failed due to invalid node format: #{node}")
        nil
    end
  end

  @impl true
  # credo:disable-for-lines:1
  def bin_path(node, app_lang, bin_service) do
    case node_info(node) do
      %Foundation.Catalog.Node{sname: @deployex_sname} ->
        Application.fetch_env!(:foundation, :bin_path)

      %Foundation.Catalog.Node{name_string: name} ->
        cond do
          bin_service == :new and app_lang in ["elixir", "erlang"] ->
            "#{new_path(node)}/bin/#{name}"

          bin_service == :new and app_lang in ["gleam"] ->
            "#{new_path(node)}/erlang-shipment"

          bin_service == :current and app_lang in ["elixir", "erlang"] ->
            "#{current_path(node)}/bin/#{name}"

          bin_service == :current and app_lang in ["gleam"] ->
            "#{current_path(node)}/erlang-shipment"

          true ->
            nil
        end

      _ ->
        nil
    end
  end

  @impl true
  def base_path, do: Application.fetch_env!(:foundation, :base_path)

  @impl true
  def new_path(node) do
    case node_info(node) do
      %Foundation.Catalog.Node{sname: sname, name_string: name} ->
        "#{service_path(name)}/#{sname}/new"

      _ ->
        nil
    end
  end

  @impl true
  def current_path(node) do
    case node_info(node) do
      %Foundation.Catalog.Node{sname: sname, name_string: name} ->
        "#{service_path(name)}/#{sname}/current"

      _ ->
        nil
    end
  end

  @impl true
  def previous_path(node) do
    case node_info(node) do
      %Foundation.Catalog.Node{sname: sname, name_string: name} ->
        "#{service_path(name)}/#{sname}/previous"

      _ ->
        nil
    end
  end

  @impl true
  def versions do
    history_version_path()
    |> list()
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  @impl true
  def versions(node) do
    Enum.filter(versions(), &(&1.node == node))
  end

  @impl true
  def add_version(version) do
    insert_by_timestamp(history_version_path(), version)
  end

  @impl true
  def ghosted_versions do
    list(ghosted_version_path())
  end

  @impl true
  def add_ghosted_version(version_map) when is_map(version_map) do
    # Retrieve current ghosted version list
    current_list = ghosted_versions()

    ghosted_version? = Enum.any?(current_list, &(&1.version == version_map.version))

    # Add the version if not in the list
    if ghosted_version? == false do
      insert_by_timestamp(ghosted_version_path(), version_map)

      {:ok, [version_map | current_list]}
    else
      {:ok, current_list}
    end
  end

  @impl true
  def config do
    get_by_key(config_path(), @config_key_file)
  end

  @impl true
  def config_update(config) do
    insert_by_key(config_path(), @config_key_file, config)

    {:ok, config}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp service_path(name), do: "#{base_path()}/service/#{name}"
  defp log_path, do: Application.fetch_env!(:foundation, :monitored_app_log_path)

  defp config_path,
    do: "#{base_path()}/storage/#{monitored_app_name()}/deployex/config"

  defp history_version_path,
    do: "#{base_path()}/storage/#{monitored_app_name()}/deployex/history"

  defp ghosted_version_path,
    do: "#{base_path()}/storage/#{monitored_app_name()}/deployex/ghosted"

  defp insert_by_timestamp(path, data) do
    file = "#{System.os_time(:microsecond)}.term"
    File.write!("#{path}/#{file}", :erlang.term_to_binary(data))
  end

  defp insert_by_key(path, key, data) do
    File.write!("#{path}/#{key}", :erlang.term_to_binary(data))
  end

  defp get_by_key(path, key) do
    case File.read("#{path}/" <> key) do
      {:ok, data} ->
        Plug.Crypto.non_executable_binary_to_term(data)

      {:error, _reason} ->
        nil
    end
  end

  defp list(path) do
    path
    |> File.ls!()
    |> Enum.map(fn file ->
      ("#{path}/" <> file)
      |> File.read!()
      |> Plug.Crypto.non_executable_binary_to_term()
    end)
  end
end
