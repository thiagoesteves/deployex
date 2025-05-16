defmodule Sentinel.Logs.Adapter do
  @moduledoc """
  Behaviour that defines the logs adapter callback
  """

  @callback subscribe_for_new_logs(String.t(), String.t()) :: :ok | {:error, term}
  @callback unsubscribe_for_new_logs(String.t(), String.t()) :: :ok
  @callback list_data_by_node_log_type(node() | String.t(), String.t(), Keyword.t()) :: list()
  @callback get_types_by_node(node()) :: list()
  @callback list_active_nodes() :: list()
end
