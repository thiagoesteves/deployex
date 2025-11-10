defmodule Sentinel.Logs do
  @moduledoc """
  This module will provide Logs server abstraction
  """

  @behaviour Sentinel.Logs.Adapter

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Subscribe for new log notifications for the respective sname/log_type
  """
  @spec subscribe_for_new_logs(String.t(), String.t()) :: :ok | {:error, term}
  def subscribe_for_new_logs(sname, log_type),
    do: default().subscribe_for_new_logs(sname, log_type)

  @doc """
  Unsubscribe for new data notifications for the respective sname/log_type
  """
  @spec unsubscribe_for_new_logs(String.t(), String.t()) :: :ok
  def unsubscribe_for_new_logs(sname, log_type),
    do: default().unsubscribe_for_new_logs(sname, log_type)

  @doc """
  Fetch data by sname and log_type
  """
  @spec list_data_by_sname_log_type(String.t(), String.t(), Keyword.t()) :: list()
  def list_data_by_sname_log_type(sname, log_type, options),
    do: default().list_data_by_sname_log_type(sname, log_type, options)

  @doc """
  List all log types registered for the respective sname
  """
  @spec get_types_by_sname(String.t()) :: list()
  def get_types_by_sname(sname), do: default().get_types_by_sname(sname)

  @doc """
  List all available snames considering the current metric configured mode
  """
  @spec list_active_snames() :: list()
  def list_active_snames, do: default().list_active_snames()

  @doc """
  Update data retention period
  """
  @spec update_data_retention_period(non_neg_integer()) :: :ok
  def update_data_retention_period(retention_period),
    do: default().update_data_retention_period(retention_period)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default,
    do: Application.get_env(:sentinel, __MODULE__)[:adapter]
end
