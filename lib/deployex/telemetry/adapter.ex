defmodule Deployex.Telemetry.Adapter do
  @moduledoc """
  Behaviour that defines the telemetry adapter callback
  """

  @callback collect_data(any()) :: :ok
  @callback subscribe_for_new_keys() :: :ok | {:error, term}
  @callback unsubscribe_for_new_keys() :: :ok
  @callback subscribe_for_new_data(String.t(), String.t()) :: :ok | {:error, term}
  @callback unsubscribe_for_new_data(String.t(), String.t()) :: :ok
  @callback list_data_by_instance(integer()) :: list()
  @callback list_data_by_instance_key(integer(), String.t(), Keyword.t()) :: list()
  @callback list_data_by_node_key(atom() | String.t(), String.t(), Keyword.t()) :: list()
  @callback get_keys_by_instance(integer()) :: list()
  @callback node_by_instance(integer()) :: nil | atom()
end
