defmodule Deployex.Observer do
  @moduledoc """
  This module will provide observability functions
  """

  require Logger

  alias Deployex.Observer.Helper
  alias Deployex.Rpc

  @link_line_color "#CCC"
  @monitor_line_color "#D1A1E5"
  @monitored_by_line_color "#4DB8FF"

  @process_symbol "emptycircle"
  @process_item_color "#93C5FD"

  @app_process_symbol "emptydiamond"
  @app_process_item_color "#A1887F"

  @supervisor_symbol "emptyroundRect"
  @supervisor_item_color "#F87171"

  @port_symbol "emptytriangle"
  @port_item_color "#FBBF24"

  @reference_symbol "emptyrect"
  @reference_item_color "#28A745"

  @type t :: %__MODULE__{
          id: pid() | port() | reference() | nil,
          children: list(),
          name: String.t(),
          symbol: String.t(),
          lineStyle: map(),
          itemStyle: map()
        }

  @derive Jason.Encoder

  defstruct id: nil,
            children: [],
            name: "",
            symbol: @process_symbol,
            lineStyle: %{color: @link_line_color},
            itemStyle: %{color: @process_item_color}

  @doc """
  Lists all running applications.
  """
  @spec list(node :: atom()) :: list({atom, String.t(), String.t()})
  def list(node \\ Node.self()) do
    Rpc.call(node, :application_controller, :which_applications, [], :infinity)
    |> Enum.filter(&alive?(node, &1))
    |> Enum.map(&structure_application/1)
  end

  @doc """
  Retreives information about the application and its respective linked processes, ports and references.
  """
  @spec info(node :: atom(), app :: atom) :: map
  def info(node \\ Node.self(), app \\ :kernel) do
    app_pid = Rpc.call(node, :application_controller, :get_master, [app], :infinity)

    children =
      node
      |> Rpc.call(:application_master, :get_child, [app_pid], :infinity)
      |> structure_id(app_pid)

    new(%{
      id: app_pid,
      children: children,
      symbol: @app_process_symbol,
      itemStyle: %{color: @app_process_item_color}
    })
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp alive?(node, {app, _, _}) do
    node
    |> Rpc.call(:application_controller, :get_master, [app], :infinity)
    |> is_pid
  catch
    # coveralls-ignore-start
    _, _ ->
      false
      # coveralls-ignore-stop
  end

  defp structure_application({name, description, version}) do
    %{
      name: name,
      description: to_string(description),
      version: to_string(version)
    }
  end

  defp structure_id({pid, name}, parent) do
    {_, dictionary} = Rpc.pinfo(pid, :dictionary)

    case Keyword.get(dictionary, :"$ancestors") do
      [ancestor_parent] ->
        child = structure_id({name, pid, :supervisor, []}, ancestor_parent)

        [
          new(%{
            id: ancestor_parent,
            children: [child],
            symbol: @app_process_symbol,
            itemStyle: %{color: @app_process_item_color}
          })
        ]

      _ ->
        # coveralls-ignore-start
        child = structure_id({name, pid, :supervisor, []}, parent)
        [child]
        # coveralls-ignore-stop
    end
  end

  defp structure_id({_, :undefined, _, _}, _parent), do: nil

  defp structure_id({_, pid, :supervisor, _}, parent) do
    {:links, links} = Rpc.pinfo(pid, :links)

    links = links -- [parent]

    children =
      pid
      |> :supervisor.which_children()
      |> Kernel.++(Enum.filter(links, fn link -> is_port(link) end))
      |> Helper.parallel_map(&structure_id(&1, pid))
      |> Enum.filter(&(&1 != nil))

    new(%{
      id: pid,
      children: children,
      symbol: @supervisor_symbol,
      itemStyle: %{color: @supervisor_item_color}
    })
  end

  defp structure_id({_, pid, :worker, _}, parent) do
    {:links, links} = Rpc.pinfo(pid, :links)
    {:monitored_by, monitored_by_pids} = Rpc.pinfo(pid, :monitored_by)
    {:monitors, monitors} = Rpc.pinfo(pid, :monitors)

    links = links -- [parent]

    children = Enum.map(links, &structure_links(&1))
    monitored_by_pids = Enum.map(monitored_by_pids, &monitored_by(&1))
    monitors = Enum.map(monitors, &monitor(&1))

    new(%{
      id: pid,
      children: children ++ monitored_by_pids ++ monitors
    })
  end

  # coveralls-ignore-start
  defp structure_id(id, _parent) when is_port(id) do
    new(%{id: id, symbol: @port_symbol})
  end

  defp structure_id(id, _parent) when is_reference(id) do
    new(%{id: id, symbol: @reference_symbol})
  end

  defp structure_id(id, _parent) do
    new(%{id: id})
  end

  # coveralls-ignore-stop

  # Check https://www.erlang.org/docs/26/man/erlang#process_info-2
  # coveralls-ignore-start
  defp monitored_by(reference) when is_reference(reference) do
    new(%{
      id: reference,
      symbol: @reference_symbol,
      itemStyle: %{color: @reference_item_color},
      lineStyle: %{color: @monitored_by_line_color}
    })
  end

  # coveralls-ignore-stop

  defp monitored_by(port) when is_port(port) do
    new(%{
      id: port,
      symbol: @port_symbol,
      itemStyle: %{color: @port_item_color},
      lineStyle: %{color: @monitored_by_line_color}
    })
  end

  defp monitored_by(pid) when is_pid(pid) do
    new(%{
      id: pid,
      lineStyle: %{color: @monitored_by_line_color}
    })
  end

  # Check https://www.erlang.org/docs/26/man/erlang#process_info-2
  # coveralls-ignore-start
  defp monitor({:port, port}) do
    new(%{
      id: port,
      lineStyle: %{color: @monitor_line_color}
    })
  end

  # coveralls-ignore-stop

  defp monitor({:process, pid}) do
    new(%{
      id: pid,
      lineStyle: %{color: @monitor_line_color}
    })
  end

  defp structure_links(port) when is_port(port) do
    new(%{
      id: port,
      symbol: @port_symbol,
      itemStyle: %{color: @port_item_color}
    })
  end

  defp structure_links(pid) when is_pid(pid) do
    new(%{id: pid})
  end

  # coveralls-ignore-start
  defp structure_links(reference) when is_reference(reference) do
    new(%{id: reference})
  end

  # coveralls-ignore-stop

  @spec new(map()) :: struct()
  def new(%{id: id} = attrs) when is_port(id) or is_pid(id) or is_reference(id) do
    name = name(id)
    struct(__MODULE__, Map.put(attrs, :name, name))
  end

  # coveralls-ignore-start
  def new(%{id: id} = attrs) do
    name = "#{inspect(id)}"
    Logger.warning("Entity ID not mapped: #{name}")

    struct(
      __MODULE__,
      attrs
      |> Map.put(:name, name)
      |> Map.put(:id, nil)
    )
  end

  # coveralls-ignore-stop

  defp name(pid) when is_pid(pid) do
    case Rpc.pinfo(pid, :registered_name) do
      {_, registered_name} -> to_string(registered_name) |> String.trim_leading("Elixir.")
      _ -> pid |> inspect |> String.trim_leading("#PID")
    end
  end

  defp name(port) when is_port(port), do: port |> inspect |> String.trim_leading("#Port")
  # coveralls-ignore-start
  defp name(reference) when is_reference(reference),
    do: reference |> inspect |> String.trim_leading("#Reference")

  # coveralls-ignore-stop
end
