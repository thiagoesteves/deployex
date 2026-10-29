defmodule Host.Commander.Adapter do
  @moduledoc """
  Behaviour that defines the Operational system adapter callback
  """

  @callback run_link(String.t(), list()) ::
              {:ok, any()} | {:ok, pid(), integer()} | {:error, any()}
  @callback run(String.t(), list()) ::
              {:ok, any()} | {:ok, pid(), integer()} | {:error, any()}
  @callback stop(integer()) :: :ok | {:error, any()}
  @callback send(integer(), String.t()) :: :ok
  @callback winsz(integer(), pos_integer(), pos_integer()) :: :ok | {:error, any()}
  @callback os_type() :: {:unix | :win32, atom()}
end
