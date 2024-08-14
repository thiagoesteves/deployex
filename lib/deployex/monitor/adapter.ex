defmodule Deployex.Monitor.Adapter do
  @moduledoc """
  Behaviour that defines the monitor adapter callback
  """

  @callback start_service(integer(), reference(), list()) ::
              {:ok, pid} | {:error, pid(), :already_started}
  @callback stop_service(integer()) :: :ok
  @callback state(integer()) :: {:ok, map()} | {:error, :rescued}
  @callback run_pre_commands(integer(), list(), :new | :current) ::
              {:ok, list()} | {:error, :rescued}
  @callback global_name(integer()) :: map()
end
