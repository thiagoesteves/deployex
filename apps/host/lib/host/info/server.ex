defmodule Host.Info.Server do
  @moduledoc """
  This server is responsible for periodically capturing system information
  and sending it to processes that are subscribed to it
  """
  use GenServer
  require Logger

  alias Host.Commander

  @update_info_interval :timer.seconds(1)
  @system_info_updated_topic "deployex::system_info_updated"

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    Logger.info("Initializing Host Memory Server")

    args
    |> Keyword.get(:update_info_interval, @update_info_interval)
    |> :timer.send_interval(:update_info)

    {:ok, %{self_node: Node.self()}}
  end

  @impl true
  def handle_info(:update_info, %{self_node: self_node} = state) do
    memory_info = memory_info(self_node)

    Phoenix.PubSub.broadcast(
      Host.PubSub,
      @system_info_updated_topic,
      {:update_system_info, memory_info}
    )

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec subscribe() :: :ok | {:error, any()}
  def subscribe, do: Phoenix.PubSub.subscribe(Host.PubSub, @system_info_updated_topic)

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp cpu_sum(cpu_list) do
    Enum.reduce(cpu_list, 0.0, fn cpu_line, acc ->
      case cpu_line |> String.trim() |> Float.parse() do
        {cpu, _} ->
          acc + cpu

        _ ->
          acc
      end
    end)
  end

  defp memory_info(self_node) do
    case Commander.os_type() do
      {:unix, :linux} ->
        # Memory Info
        {:ok, [{:stdout, stdout}]} = Commander.run("free -b", [:stdout, :sync])

        free_list =
          stdout |> Enum.join() |> String.split("\n", trim: true) |> Enum.at(1) |> String.split()

        memory_total = free_list |> Enum.at(1) |> String.to_integer()
        memory_free = free_list |> Enum.at(6) |> String.to_integer()

        # Number of CPUs
        {:ok, [{:stdout, stdout}]} = Commander.run("nproc", [:stdout, :sync])
        cpus = stdout |> Enum.join() |> String.trim() |> String.to_integer()

        # CPU utilization
        {:ok, [{:stdout, stdout}]} = Commander.run("ps -eo pcpu", [:stdout, :sync])

        [_title | cpu_utilization] =
          stdout
          |> Enum.join()
          |> String.split("\n", trim: true)

        cpu = cpu_sum(cpu_utilization)

        # Host OS description
        {:ok, [{:stdout, stdout}]} =
          Commander.run("cat /etc/os-release | grep VERSION= | sed 's/VERSION=//; s/\"//g'", [
            :stdout,
            :sync
          ])

        description = stdout |> Enum.join() |> String.trim()

        %Host.Info{
          host: "Linux",
          source_node: self_node,
          description: description,
          memory_free: memory_free,
          memory_total: memory_total,
          cpus: cpus,
          cpu: Float.round(cpu, 2)
        }

      {:unix, :darwin} ->
        # Memory Info
        {:ok, [{:stdout, stdout}]} = Commander.run("vm_stat", [:stdout, :sync])
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

        {:ok, [{:stdout, stdout}]} = Commander.run("sysctl -n hw.memsize", [:stdout, :sync])
        memory_total = stdout |> Enum.join() |> String.trim() |> String.to_integer()

        # Number of CPUs
        {:ok, [{:stdout, stdout}]} = Commander.run("sysctl -n hw.ncpu", [:stdout, :sync])
        cpus = stdout |> Enum.join() |> String.trim() |> String.to_integer()

        # CPU utilization
        {:ok, [{:stdout, stdout}]} = Commander.run("ps -A -o %cpu", [:stdout, :sync])

        [_title | cpu_utilization] =
          stdout
          |> Enum.join()
          |> String.split("\n", trim: true)

        cpu = cpu_sum(cpu_utilization)

        # Host OS description
        {:ok, [{:stdout, stdout}]} = Commander.run("sw_vers -productVersion", [:stdout, :sync])
        description = stdout |> Enum.join() |> String.trim()

        %Host.Info{
          host: "macOS",
          source_node: self_node,
          description: description,
          memory_free: page_size * page_free,
          memory_total: memory_total,
          cpus: cpus,
          cpu: Float.round(cpu, 2)
        }

      {:win32, _} ->
        %Host.Info{host: "Windows", source_node: self_node}
    end
  end
end
