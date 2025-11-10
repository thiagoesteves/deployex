defmodule Sentinel.Logs.Adapter do
  @moduledoc """
  Behaviour that defines the logs adapter callback
  """

  @callback subscribe_for_new_logs(String.t(), String.t()) :: :ok | {:error, term}
  @callback unsubscribe_for_new_logs(String.t(), String.t()) :: :ok
  @callback list_data_by_sname_log_type(String.t(), String.t(), Keyword.t()) :: list()
  @callback get_types_by_sname(String.t()) :: list()
  @callback list_active_snames() :: list()
  @callback update_data_retention_period(non_neg_integer()) :: :ok
end
