defmodule Deployex.Logs do
  @moduledoc """
  This module will provide Logs server abstraction
  """

  @behaviour Deployex.Logs.Adapter

  defmodule Message do
    @moduledoc """
    Structure to handle the log event
    """
    @type t :: %__MODULE__{
            timestamp: non_neg_integer(),
            log: nil | String.t()
          }

    defstruct timestamp: nil,
              log: nil
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Subscribe for new log types notifications
  """
  @spec subscribe_for_new_log_types() :: :ok | {:error, term}
  def subscribe_for_new_log_types, do: default().subscribe_for_new_log_types()

  @doc """
  Subscribe for new log notifications for the respective node/log_type
  """
  @spec subscribe_for_new_logs(String.t(), String.t()) :: :ok | {:error, term}
  def subscribe_for_new_logs(node, log_type), do: default().subscribe_for_new_logs(node, log_type)

  @doc """
  Unsubscribe for new data notifications for the respective node/log_type
  """
  @spec unsubscribe_for_new_logs(String.t(), String.t()) :: :ok
  def unsubscribe_for_new_logs(node, log_type),
    do: default().unsubscribe_for_new_logs(node, log_type)

  @doc """
  Fetch data by node and log_type
  """
  @spec list_data_by_node_log_type(atom() | String.t(), String.t(), Keyword.t()) :: list()
  def list_data_by_node_log_type(node, log_type, options),
    do: default().list_data_by_node_log_type(node, log_type, options)

  @doc """
  List all log types registered for the respective node
  """
  @spec get_types_by_node(atom()) :: list()
  def get_types_by_node(node), do: default().get_types_by_node(node)

  @doc """
  List all available nodes considering the current metric configured mode
  """
  @spec list_active_nodes() :: list()
  def list_active_nodes, do: default().list_active_nodes()

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default,
    do: Application.get_env(:deployex, __MODULE__)[:adapter]
end
