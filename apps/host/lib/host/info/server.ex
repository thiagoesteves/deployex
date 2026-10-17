defmodule Host.Info.Server do
  @moduledoc """
  This server is responsible for periodically capturing host information
  and sending it to processes that are subscribed to it
  """
  use GenServer
  require Logger

  alias Host.Commander

  alias Host.Info.Cpu
  alias Host.Info.Description
  alias Host.Info.Memory
  alias Host.Info.Uptime

  @update_info_interval :timer.seconds(1)
  @system_info_updated_topic "deployex::host_info_updated"

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

    # The table takes the server name, so each server keeps its own last reading
    table = Keyword.get(args, :name, __MODULE__)
    :ets.new(table, [:set, :protected, :named_table])

    {:ok, %{self_node: Node.self(), table: table}}
  end

  @impl true
  def handle_info(:update_info, %{self_node: self_node, table: table} = state) do
    host_info = host_info(self_node)

    :ets.insert(table, {:host_info, host_info})

    Phoenix.PubSub.broadcast(
      Host.PubSub,
      @system_info_updated_topic,
      {:update_system_info, host_info}
    )

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec subscribe() :: :ok | {:error, any()}
  def subscribe, do: Phoenix.PubSub.subscribe(Host.PubSub, @system_info_updated_topic)

  @doc """
  Returns the last host reading, or nil before the first one or with no server running.
  """
  @spec latest(name :: atom()) :: Host.Info.t() | nil
  def latest(name \\ __MODULE__) do
    with tid when tid != :undefined <- :ets.whereis(name),
         [{:host_info, host_info}] <- :ets.lookup(tid, :host_info) do
      host_info
    else
      _ -> nil
    end
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp host_info(self_node) do
    host_info = %Host.Info{source_node: self_node}

    {memory, cpu, uptime, description} =
      case Commander.os_type() do
        {:unix, :linux} ->
          {Memory.get_linux(), Cpu.get_linux(), Uptime.get_linux(), Description.get_linux()}

        {:unix, :darwin} ->
          {Memory.get_macos(), Cpu.get_macos(), Uptime.get_macos(), Description.get_macos()}

        {:win32, _} ->
          {Memory.get_windows(), Cpu.get_windows(), Uptime.get_windows(),
           Description.get_windows()}
      end

    host_info
    |> struct(Map.from_struct(memory))
    |> struct(Map.from_struct(cpu))
    |> struct(Map.from_struct(uptime))
    |> struct(Map.from_struct(description))
  end
end
