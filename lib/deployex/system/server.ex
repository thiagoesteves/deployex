defmodule Deployex.System.Server do
  @moduledoc """
  This server is responsible for periodically capturing system information
  and sending it to processes that are subscribed to it
  """
  use GenServer
  require Logger

  alias Deployex.OpSys

  @update_info_interval :timer.seconds(1)
  @system_info_updated_topic "system_info_updated"

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    Logger.info("Initializing System Server")

    state = memory_info()

    args
    |> Keyword.get(:update_info_interval, @update_info_interval)
    |> :timer.send_interval(:update_info)

    {:ok, state}
  end

  @impl true
  def handle_info(:update_info, _state) do
    state = memory_info()

    Phoenix.PubSub.broadcast(
      Deployex.PubSub,
      @system_info_updated_topic,
      {:update_system_info, state}
    )

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec subscribe() :: :ok | {:error, any()}
  def subscribe, do: Phoenix.PubSub.subscribe(Deployex.PubSub, @system_info_updated_topic)

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp cpu_sum(cpu_list) do
    Enum.reduce(cpu_list, 0.0, fn cpu_line, acc ->
      case cpu_line |> String.trim() |> Float.parse() do
        {cpu, _} ->
          acc + cpu

        # coveralls-ignore-start
        _ ->
          acc
          # coveralls-ignore-stop
      end
    end)
  end

  defp memory_info do
    case OpSys.os_type() do
      {:unix, :linux} ->
        # Memory Info
        {:ok, [{:stdout, stdout}]} = OpSys.run("free -b", [:stdout, :sync])

        free_list =
          stdout |> Enum.join() |> String.split("\n", trim: true) |> Enum.at(1) |> String.split()

        memory_total = free_list |> Enum.at(1) |> String.to_integer()
        memory_free = free_list |> Enum.at(6) |> String.to_integer()

        # Number of CPUs
        {:ok, [{:stdout, stdout}]} = OpSys.run("nproc", [:stdout, :sync])
        cpus = stdout |> Enum.join() |> String.trim() |> String.to_integer()

        # CPU utilization
        {:ok, [{:stdout, stdout}]} = OpSys.run("ps -eo pcpu", [:stdout, :sync])

        [_title | cpu_utilization] =
          stdout
          |> Enum.join()
          |> String.split("\n", trim: true)

        cpu = cpu_sum(cpu_utilization)

        # Host OS description
        {:ok, [{:stdout, stdout}]} =
          OpSys.run("cat /etc/os-release | grep VERSION= | sed 's/VERSION=//; s/\"//g'", [
            :stdout,
            :sync
          ])

        description = stdout |> Enum.join() |> String.trim()

        %Deployex.System{
          host: "Linux",
          description: description,
          memory_free: memory_free,
          memory_total: memory_total,
          cpus: cpus,
          cpu: trunc(cpu)
        }

      {:unix, :darwin} ->
        # Memory Info
        {:ok, [{:stdout, stdout}]} = OpSys.run("vm_stat", [:stdout, :sync])
        info_list = stdout |> Enum.join() |> String.split("\n")

        [page_size_text] =
          String.split(
            Enum.at(info_list, 0),
            ["Mach Virtual Memory Statistics: (page size of ", " bytes)"],
            trim: true
          )

        [page_free_text] = String.split(Enum.at(info_list, 1), ["Pages free:", "."], trim: true)

        page_size = page_size_text |> String.trim() |> String.to_integer()
        page_free = page_free_text |> String.trim() |> String.to_integer()

        {:ok, [{:stdout, stdout}]} = OpSys.run("sysctl -n hw.memsize", [:stdout, :sync])
        memory_total = stdout |> Enum.join() |> String.trim() |> String.to_integer()

        # Number of CPUs
        {:ok, [{:stdout, stdout}]} = OpSys.run("sysctl -n hw.ncpu", [:stdout, :sync])
        cpus = stdout |> Enum.join() |> String.trim() |> String.to_integer()

        # CPU utilization
        {:ok, [{:stdout, stdout}]} = OpSys.run("ps -A -o %cpu", [:stdout, :sync])

        [_title | cpu_utilization] =
          stdout
          |> Enum.join()
          |> String.split("\n", trim: true)

        cpu = cpu_sum(cpu_utilization)

        # Host OS description
        {:ok, [{:stdout, stdout}]} = OpSys.run("sw_vers -productVersion", [:stdout, :sync])
        description = stdout |> Enum.join() |> String.trim()

        %Deployex.System{
          host: "macOS",
          description: description,
          memory_free: page_size * page_free,
          memory_total: memory_total,
          cpus: cpus,
          cpu: trunc(cpu)
        }

      {:win32, _} ->
        %Deployex.System{host: "Windows"}
    end
  end
end
