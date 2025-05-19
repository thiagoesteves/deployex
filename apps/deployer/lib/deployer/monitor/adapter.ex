defmodule Deployer.Monitor.Adapter do
  @moduledoc """
  Behaviour that defines the monitor adapter callback
  """

  @callback start_service(String.t(), String.t(), non_neg_integer(), list()) ::
              {:ok, pid} | {:error, pid(), :already_started}
  @callback stop_service(String.t() | nil) :: :ok
  @callback restart(String.t()) :: :ok | {:error, :application_is_not_running}
  @callback state(String.t()) :: Deployer.Monitor.t()
  @callback subscribe_new_deploy() :: :ok
  @callback list() :: list()
  @callback run_pre_commands(String.t(), list(), :new | :current) ::
              {:ok, list()} | {:error, :rescued}
  @callback global_name(String.t()) :: map()
end
