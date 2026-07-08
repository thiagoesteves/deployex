defmodule DeployexWeb.Cache do
  @moduledoc """
  GenServer that holds deployex_web cache
  """
  use GenServer

  @table_name :web_cache_table

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    :ets.new(@table_name, [:set, :protected, :named_table])

    {:ok, %{}}
  end

  @impl true
  def handle_call({:update_data, key, data}, _from, state) do
    :ets.insert(@table_name, {key, data})
    {:reply, :ok, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{_, value}] ->
        value

      _ ->
        nil
    end
  end

  # NOTE: The write is a synchronous call so that a subsequent get/1 is
  #       guaranteed to observe it, get/1 reads the ETS table directly.
  def set(key, data) do
    GenServer.call(__MODULE__, {:update_data, key, data})
  end
end
