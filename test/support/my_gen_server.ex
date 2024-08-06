defmodule Deployex.MyGenServer do
  @moduledoc false
  use GenServer

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(_, _from, state) do
    {:reply, :ok, state}
  end
end
