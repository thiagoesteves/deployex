defmodule Foundation.Catalog.Local do
  @moduledoc """
  This module handles the storage information using local files and ets tables
  for temporary data
  """

  use GenServer

  alias Foundation.Catalog
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

  def setup_new_app(name) do
    File.mkdir_p!(config_path(name))
    File.mkdir_p!(history_version_path(name))
    File.mkdir_p!(ghosted_version_path(name))

    :ok
  end

  @impl true
  def setup do
    applications()
    |> Enum.each(fn %{name: name} ->
      # Create paths to store persistent information
      File.mkdir_p!(config_path(name))
      File.mkdir_p!(history_version_path(name))
      File.mkdir_p!(ghosted_version_path(name))
    end)

    :ok
  end

  @impl true
  def setup(sname) do
    case node_info(sname) do
      %{name: name} ->
        [new_path(sname), current_path(sname), previous_path(sname)]
        |> Enum.each(&File.mkdir_p!/1)

        File.mkdir_p!("#{log_path()}/#{name}")
        File.touch(stdout_path(sname))
        File.touch(stderr_path(sname))

        :ok

      nil ->
        :ok
    end
  end

  @impl true
  def cleanup(nil), do: :ok

  def cleanup(sname) do
    case node_info(sname) do
      %{name: name} ->
        File.rm_rf("#{service_path(name)}/#{sname}")
        :ok

      nil ->
        :ok
    end
  end

  @impl true
  def applications, do: Application.fetch_env!(:foundation, :applications)

  @impl true
  def create_sname(name) do
    suffix = Common.random_small_alphanum()
    "#{name}-#{suffix}"
  end

  @impl true
  def node_info(nil), do: nil

  def node_info(node_or_sname) when is_atom(node_or_sname) do
    node_or_sname |> Atom.to_string() |> node_info()
  end

  def node_info(node_or_sname) do
    parse_sname = fn sname, node, hostname ->
      case String.split(sname, ["-"]) do
        [name, suffix] ->
          # credo:disable-for-lines:1
          case Enum.find(applications(), &(&1.name == name)) do
            %{language: language} ->
              %Catalog.Node{
                node: node,
                sname: sname,
                name: name,
                hostname: hostname,
                suffix: suffix,
                language: language
              }

            _ ->
              nil
          end

        [name] when name in [@deployex_sname, @nohost_sname] ->
          %Catalog.Node{
            node: Node.self(),
            sname: @deployex_sname,
            name: @deployex_sname,
            hostname: hostname,
            suffix: "",
            language: "elixir"
          }

        _ ->
          nil
      end
    end

    case String.split(node_or_sname, ["@"]) do
      [sname, hostname] ->
        node = String.to_atom("#{sname}@#{hostname}")
        parse_sname.(sname, node, hostname)

      [sname] ->
        {:ok, hostname} = :inet.gethostname()
        node = String.to_atom("#{sname}@#{hostname}")
        parse_sname.(sname, node, hostname)
    end
  end

  @impl true
  def stdout_path(@deployex_sname) do
    log_path = Application.fetch_env!(:foundation, :log_path)
    "#{log_path}/deployex-stdout.log"
  end

  def stdout_path(sname) do
    case node_info(sname) do
      %{name: name} ->
        log_path = Application.fetch_env!(:foundation, :monitored_app_log_path)
        "#{log_path}/#{name}/#{sname}-stdout.log"

      _ ->
        nil
    end
  end

  @impl true
  def stderr_path(@deployex_sname) do
    log_path = Application.fetch_env!(:foundation, :log_path)
    "#{log_path}/deployex-stderr.log"
  end

  def stderr_path(sname) do
    case node_info(sname) do
      %{name: name} ->
        log_path = Application.fetch_env!(:foundation, :monitored_app_log_path)
        "#{log_path}/#{name}/#{sname}-stderr.log"

      _ ->
        nil
    end
  end

  @impl true
  def bin_path(@deployex_sname, _bin_service) do
    Application.fetch_env!(:foundation, :bin_path)
  end

  # credo:disable-for-lines:1
  def bin_path(sname, bin_service) do
    %{name: name, language: language} = node_info(sname)

    cond do
      bin_service == :new and language in ["elixir", "erlang"] ->
        "#{new_path(sname)}/bin/#{name}"

      bin_service == :new and language in ["gleam"] ->
        "#{new_path(sname)}/erlang-shipment"

      bin_service == :current and language in ["elixir", "erlang"] ->
        "#{current_path(sname)}/bin/#{name}"

      bin_service == :current and language in ["gleam"] ->
        "#{current_path(sname)}/erlang-shipment"

      true ->
        nil
    end
  end

  @impl true
  def service_path(name), do: "#{base_path()}/service/#{name}"

  @impl true
  def new_path(nil), do: nil

  def new_path(sname) do
    %{name: name} = node_info(sname)
    "#{service_path(name)}/#{sname}/new"
  end

  @impl true
  def current_path(nil), do: nil

  def current_path(sname) do
    %{name: name} = node_info(sname)
    "#{service_path(name)}/#{sname}/current"
  end

  @impl true
  def previous_path(nil), do: nil

  def previous_path(sname) do
    %{name: name} = node_info(sname)
    "#{service_path(name)}/#{sname}/previous"
  end

  @impl true
  def versions(name, options) do
    sname = Keyword.get(options, :sname)

    sorted_list =
      name
      |> history_version_path()
      |> list()
      |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})

    if sname do
      Enum.filter(sorted_list, &(&1.sname == sname))
    else
      sorted_list
    end
  end

  @impl true
  def add_version(%{name: name} = version) do
    name
    |> history_version_path()
    |> insert_by_timestamp(version)
  end

  @impl true
  def ghosted_versions(name) do
    name
    |> ghosted_version_path()
    |> list()
  end

  @impl true
  def add_ghosted_version(version_map) when is_map(version_map) do
    # Retrieve current ghosted version list
    current_list = ghosted_versions(version_map.name)

    ghosted_version? = Enum.any?(current_list, &(&1.version == version_map.version))

    # Add the version if not in the list
    if ghosted_version? == false do
      version_map.name
      |> ghosted_version_path()
      |> insert_by_timestamp(version_map)

      {:ok, [version_map | current_list]}
    else
      {:ok, current_list}
    end
  end

  @impl true
  def config(name) do
    name
    |> config_path()
    |> get_by_key(@config_key_file)
  end

  @impl true
  def config_update(name, config) do
    name
    |> config_path()
    |> insert_by_key(@config_key_file, config)

    {:ok, config}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp base_path, do: Application.fetch_env!(:foundation, :base_path)
  defp log_path, do: Application.fetch_env!(:foundation, :monitored_app_log_path)

  defp config_path(name),
    do: "#{base_path()}/storage/#{name}/deployex/config"

  defp history_version_path(name),
    do: "#{base_path()}/storage/#{name}/deployex/history"

  defp ghosted_version_path(name),
    do: "#{base_path()}/storage/#{name}/deployex/ghosted"

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
