defmodule Sentinel.BeamVm.Server do
  @moduledoc """
  This server is responsible for periodically capturing system information
  and sending it to processes that are subscribed to it
  """
  use GenServer
  require Logger

  alias Foundation.Rpc

  @update_info_interval :timer.seconds(1)
  @timeout 100
  @beam_vm_info_updated_topic "beam_vm_info_updated"

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    Logger.info("Initialising Beam VM Statistics Server")

    state = %{} # application_info()

    args
    |> Keyword.get(:update_info_interval, @update_info_interval)
    |> :timer.send_interval(:update_info)

    {:ok, state}
  end

  @impl true
  def handle_info(:update_info, _state) do
    state = %{} # application_info()

    Phoenix.PubSub.broadcast(
      Sentinel.PubSub,
      @beam_vm_info_updated_topic,
      {:beam_vm_info, state}
    )

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec subscribe() :: :ok | {:error, any()}
  def subscribe, do: Phoenix.PubSub.subscribe(Sentinel.PubSub, @beam_vm_info_updated_topic)

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  def application_info(node) do
    total_memory =
      case Rpc.call(node, :erlang, :memory, [], @timeout) do
        [_head | _rest] = memory ->
          memory[:total]

        _error ->
          nil
      end

    get_value_from_node = fn field ->
      case Rpc.call(node, :erlang, :system_info, [field], @timeout) do
        value when is_number(value) ->
          value

        _error ->
          nil
      end
    end

    %{
      total_memory: total_memory,
      port_limit: get_value_from_node.(:port_limit),
      port_count: get_value_from_node.(:port_count),
      atom_count: get_value_from_node.(:atom_count),
      atom_limit: get_value_from_node.(:atom_limit),
      process_limit: get_value_from_node.(:process_limit),
      process_count: get_value_from_node.(:process_count)
    }
  end
end
