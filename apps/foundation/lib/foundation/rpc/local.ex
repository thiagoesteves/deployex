defmodule Foundation.Rpc.Local do
  @moduledoc """
    Local Rpc implementation
  """

  @behaviour Foundation.Rpc.Adapter

  ### ==========================================================================
  ### Rpc Callbacks
  ### ==========================================================================
  @doc """
  Execute the OTP rpc function

  ## Examples

    iex> alias Foundation.Rpc.Local
    ...> assert [_head | _rest] = Local.call(:nonode@nohost, :erlang, :memory, [], 1000)
  """
  @impl true
  def call(node, module, function, args, timeout) do
    :rpc.call(node, module, function, args, timeout)
  end
end
