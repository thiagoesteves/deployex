defmodule Deployex.OpSys.Adapter do
  @moduledoc """
  Behaviour that defines the Operational system adapter callback
  """

  @callback run_link(String.t(), list()) ::
              {:ok, any()} | {:ok, pid(), integer()} | {:error, any()}
  @callback run(String.t(), list()) ::
              {:ok, any()} | {:ok, pid(), integer()} | {:error, any()}
  @callback stop(integer()) :: :ok | {:error, any()}
  @callback send(integer(), String.t()) :: :ok
end
