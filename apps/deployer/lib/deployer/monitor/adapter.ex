defmodule Deployer.Monitor.Adapter do
  @moduledoc """
  Behaviour that defines the monitor adapter callback
  """

  @callback start_service(String.t(), integer(), String.t(), list()) ::
              {:ok, pid} | {:error, pid(), :already_started}
  @callback stop_service(integer()) :: :ok
  @callback restart(integer()) :: :ok | {:error, :application_is_not_running}
  @callback state(integer()) :: Deployer.Monitor.t()
  @callback run_pre_commands(integer(), list(), :new | :current) ::
              {:ok, list()} | {:error, :rescued}
  @callback global_name(integer()) :: [map()]
  @callback global_name(integer(), String.t()) :: map()
end
