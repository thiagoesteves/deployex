defmodule Deployer.Monitor.Adapter do
  @moduledoc """
  Behaviour that defines the monitor adapter callback
  """

  @callback start_service(node(), String.t(), non_neg_integer(), list()) ::
              {:ok, pid} | {:error, pid(), :already_started}
  @callback stop_service(node()) :: :ok
  @callback restart(node()) :: :ok | {:error, :application_is_not_running}
  @callback state(node()) :: Deployer.Monitor.t()
  @callback subscribe_new_deploy() :: :ok
  @callback list() :: list()
  @callback run_pre_commands(node(), list(), :new | :current) ::
              {:ok, list()} | {:error, :rescued}
  @callback global_name(node()) :: map()
end
