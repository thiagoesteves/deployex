defmodule Deployex.Status.Adapter do
  @moduledoc """
  Behaviour that defines the status adapter callback
  """

  alias Deployex.Release
  alias Deployex.Status

  @callback state :: {:ok, map()} | {:error, :rescued}
  @callback current_version(integer()) :: String.t() | nil
  @callback current_version_map(integer()) :: Status.deployex_version_map() | nil
  @callback listener_topic() :: String.t()
  @callback set_current_version_map(integer(), Release.Version.t(), Keyword.t()) :: :ok
  @callback add_ghosted_version(Status.deployex_version_map()) :: {:ok, list()}
  @callback ghosted_version_list :: list()
  @callback history_version_list :: list()
  @callback history_version_list(integer() | binary()) :: list()
  @callback clear_new(integer()) :: :ok
  @callback update(integer()) :: :ok
  @callback mode() :: {:ok, map()} | {:error, :rescued}
  @callback set_mode(:automatic | :manual, map()) :: {:ok, map()}
end
