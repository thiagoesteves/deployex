defmodule Deployex.Rpc do
  @moduledoc """
  This module will provide rpc abstraction
  """

  @behaviour Deployex.Rpc.Adapter

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Run the passed commands and link the process with the genserver calling
  gen_server for supervision
  """
  @impl true
  @spec call(
          node :: atom,
          module :: module,
          function :: atom,
          args :: list,
          timeout :: 0..4_294_967_295 | :infinity
        ) :: any() | {:badrpc, any()}
  def call(node, module, function, args, timeout),
    do: default().call(node, module, function, args, timeout)

  @doc """
  Call :rpc.pinfo to request process information (local or remote pid)

  Location transparent version of the BIF :erlang.process_info/2

  https://www.erlang.org/doc/apps/kernel/rpc.html#pinfo/1
  """
  @impl true
  @spec pinfo(pid :: pid, information :: list | atom()) :: any() | :undefined
  def pinfo(pid, information),
    do: default().pinfo(pid, information)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]
end
