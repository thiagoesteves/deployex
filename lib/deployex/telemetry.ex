defmodule Deployex.Telemetry do
  @moduledoc """
  This module will provide telemetry abstraction
  """

  @behaviour Deployex.Telemetry.Adapter

  defmodule Data do
    @moduledoc """
    Structure to handle the telemetry event
    """
    @type t :: %__MODULE__{
            timestamp: non_neg_integer(),
            value: integer() | float(),
            unit: String.t(),
            tags: map(),
            measurements: map()
          }

    defstruct timestamp: nil,
              value: "",
              unit: "",
              tags: %{},
              measurements: %{}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  This function pushes events to the Telemetry module, it is expected
  to be called via RPC.
  """
  # coveralls-ignore-start
  @spec push_data(any()) :: :ok
  def push_data(event), do: default().push_data(event)
  # coveralls-ignore-stop

  @doc """
  Subscribe for new keys notifications
  """
  @spec subscribe_for_new_keys() :: :ok | {:error, term}
  def subscribe_for_new_keys, do: default().subscribe_for_new_keys()

  @doc """
  Subscribe for new data notifications for the respective node/key
  """
  @spec subscribe_for_new_data(String.t(), String.t()) :: :ok | {:error, term}
  def subscribe_for_new_data(node, key), do: default().subscribe_for_new_data(node, key)

  @doc """
  Unsubscribe for new data notifications for the respective node/key
  """
  @spec unsubscribe_for_new_data(String.t(), String.t()) :: :ok
  def unsubscribe_for_new_data(node, key), do: default().unsubscribe_for_new_data(node, key)

  @doc """
  Fetch data by node and key
  """
  @spec list_data_by_node_key(atom() | String.t(), String.t(), Keyword.t()) :: list()
  def list_data_by_node_key(node, key, options),
    do: default().list_data_by_node_key(node, key, options)

  @doc """
  List all keys registered for the respective instance
  """
  @spec get_keys_by_instance(integer()) :: list()
  def get_keys_by_instance(instance), do: default().get_keys_by_instance(instance)

  @doc """
  Retrieve the repective noce registered for the passed instance
  """
  @spec node_by_instance(integer()) :: nil | atom()
  def node_by_instance(instance), do: default().node_by_instance(instance)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]
end
