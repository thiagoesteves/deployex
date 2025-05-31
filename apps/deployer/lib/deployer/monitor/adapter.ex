defmodule Deployer.Monitor.Adapter do
  @moduledoc """
  Behaviour that defines the monitor adapter callback
  """

  alias Deployer.Monitor

  @type bin_path :: :new | :current

  @callback start_service(Monitor.Service.t()) :: {:ok, pid} | {:error, pid(), :already_started}
  @callback stop_service(String.t() | nil, String.t() | nil) :: :ok
  @callback restart(String.t()) :: :ok | {:error, :application_is_not_running}
  @callback state(String.t()) :: Monitor.t()
  @callback subscribe_new_deploy() :: :ok
  @callback list() :: list()
  @callback list(Keyword.t()) :: list()
  @callback run_pre_commands(String.t(), list(), bin_path()) :: {:ok, list()} | {:error, :rescued}
end
