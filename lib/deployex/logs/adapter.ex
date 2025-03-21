defmodule Deployex.Logs.Adapter do
  @moduledoc """
  Behaviour that defines the telemetry adapter callback
  """

  @callback subscribe_for_new_log_types() :: :ok | {:error, term}
  @callback subscribe_for_new_logs(String.t(), String.t()) :: :ok | {:error, term}
  @callback unsubscribe_for_new_logs(String.t(), String.t()) :: :ok
  @callback list_data_by_node_log_type(atom() | String.t(), String.t(), Keyword.t()) :: list()
  @callback get_types_by_node(atom()) :: list()
  @callback list_active_nodes() :: list()
end
