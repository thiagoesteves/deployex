defmodule Deployex.Observer do
  @moduledoc """
  This module will provide observability functions
  """

  alias Deployex.Observer.Helper
  alias Deployex.Observer.Port
  alias Deployex.Observer.Process

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
          pid: pid() | nil,
          children: list(),
          name: String.t(),
          symbol: String.t(),
          lineStyle: map(),
          itemStyle: map(),
          meta: map()
        }

  @derive Jason.Encoder

  defstruct pid: nil,
            children: [],
            name: "",
            symbol: @process_symbol,
            lineStyle: %{color: @link_line_color},
            itemStyle: %{color: @process_item_color},
            meta: %{}

  @doc """
  Lists all running applications.

  The application information is given as a tuple containing: `{name, description, version}`.
  The `name` is an atom, while both the description and version are Strings.
  """
  @spec list :: list({atom, String.t(), String.t()})
  def list do
    :application_controller.which_applications()
    |> Enum.filter(&alive?/1)
    |> Enum.map(&structure_application/1)
  end

  @doc """
  Retreives information about the application.

  The given `app` atom is used to find the started application.

  Containing:
    - `pid`, the process id or port id.
    - `name`, the registered name or pid/port.
    - `meta`,  the meta information of a process. (See: `Wobserver.Util.Process.meta/1`.)
    - `children`, the children of the process.
  """
  @spec info(app :: atom) :: map
  def info(app \\ :kernel) do
    app_pid =
      app
      |> :application_controller.get_master()

    children = app_pid |> :application_master.get_child() |> structure_pid(app_pid)

    new(%{
      pid: app_pid,
      name: name(app_pid),
      children: children,
      symbol: @app_process_symbol,
      itemStyle: %{color: @app_process_item_color},
      meta: meta(app_pid)
    })
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp alive?({app, _, _}) do
    app
    |> :application_controller.get_master()
    |> is_pid
  catch
    _, _ -> false
  end

  defp structure_application({name, description, version}) do
    %{
      name: name,
      description: to_string(description),
      version: to_string(version)
    }
  end

  defp structure_pid({pid, name}, parent) do
    child = structure_pid({name, pid, :supervisor, []}, parent)

    {_, dictionary} = :erlang.process_info(pid, :dictionary)

    case Keyword.get(dictionary, :"$ancestors") do
      [parent] ->
        child = structure_pid({name, pid, :supervisor, []}, parent)

        [
          new(%{
            pid: parent,
            name: name(parent),
            children: [child],
            symbol: @app_process_symbol,
            itemStyle: %{color: @app_process_item_color},
            meta: meta(parent)
          })
        ]

      _ ->
        raise "error"
        [child]
    end
  end

  defp structure_pid({_, :undefined, _, _}, _parent), do: nil

  defp structure_pid({_, pid, :supervisor, _}, parent) do
    {:links, links} = :erlang.process_info(pid, :links)

    links = links -- [parent]

    children =
      pid
      |> :supervisor.which_children()
      |> Kernel.++(Enum.filter(links, fn link -> is_port(link) end))
      |> Helper.parallel_map(&structure_pid(&1, pid))
      |> Enum.filter(&(&1 != nil))

    new(%{
      pid: pid,
      name: name(pid),
      children: children,
      symbol: @supervisor_symbol,
      itemStyle: %{color: @supervisor_item_color},
      meta: meta(pid)
    })
  end

  defp structure_pid({_, pid, :worker, _}, parent) do
    {:links, links} = :rpc.pinfo(pid, :links)
    {:monitored_by, monitored_by_pids} = :rpc.pinfo(pid, :monitored_by)
    {:monitors, monitors} = :rpc.pinfo(pid, :monitors)

    links = links -- [parent]

    children = Enum.map(links, &structure_pid_or_port/1)
    monitored_by_pids = Enum.map(monitored_by_pids, &monitored_by/1)
    monitors = Enum.map(monitors, &monitor/1)

    new(%{
      pid: pid,
      name: name(pid),
      children: children ++ monitored_by_pids ++ monitors,
      meta: meta(pid)
    })
  end

  # Check https://www.erlang.org/docs/26/man/erlang#process_info-2
  defp monitored_by(reference) when is_reference(reference) do
    new(%{
      pid: reference,
      name: print_reference(reference),
      symbol: @reference_symbol,
      itemStyle: %{color: @reference_item_color},
      lineStyle: %{color: @monitored_by_line_color}
    })
  end

  defp monitored_by(port) when is_port(port) do
    new(%{
      pid: port,
      name: print_port(port),
      symbol: @port_symbol,
      itemStyle: %{color: @port_item_color},
      lineStyle: %{color: @monitored_by_line_color},
      meta: meta(port)
    })
  end

  defp monitored_by(pid) when is_pid(pid) do
    new(%{
      pid: pid,
      name: print_pid(pid),
      lineStyle: %{color: @monitored_by_line_color},
      meta: meta(pid)
    })
  end

  # Check https://www.erlang.org/docs/26/man/erlang#process_info-2
  defp monitor({:port, port}) do
    new(%{
      pid: port,
      name: print_port(port),
      lineStyle: %{color: @monitor_line_color},
      meta: meta(port)
    })
  end

  defp monitor({:process, pid}) do
    new(%{
      pid: pid,
      name: print_pid(pid),
      lineStyle: %{color: @monitor_line_color},
      meta: meta(pid)
    })
  end

  defp structure_pid_or_port(port) when is_port(port) do
    new(%{
      pid: port,
      name: name(port),
      symbol: @port_symbol,
      itemStyle: %{color: @port_item_color},
      meta: meta(port)
    })
  end

  defp structure_pid_or_port(pid) when is_pid(pid) do
    new(%{pid: pid, name: name(pid), meta: meta(pid)})
  end

  defp structure_pid_or_port(_), do: nil

  defp name(pid) when is_pid(pid) do
    case :rpc.pinfo(pid, :registered_name) do
      {_, registered_name} -> to_string(registered_name) |> String.trim_leading("Elixir.")
      _ -> print_pid(pid)
    end
  end

  defp name(port) when is_port(port), do: print_port(port)

  defp print_pid(pid), do: pid |> inspect |> String.trim_leading("#PID")
  defp print_port(port), do: port |> inspect |> String.trim_leading("#Port")
  defp print_reference(reference), do: reference |> inspect |> String.trim_leading("#Reference")

  @spec new(map()) :: struct()
  def new(attrs \\ %{}) do
    struct(__MODULE__, attrs)
  end

  defp meta(pid) when is_pid(pid), do: Process.meta(pid)
  defp meta(port) when is_port(port), do: Port.meta(port)
end