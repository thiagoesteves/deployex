defmodule Deployex.Storage.Adapter do
  @moduledoc """
  Behaviour that defines the storage adapter callback
  """

  @callback init() :: :ok
  @callback replicas() :: integer()
  @callback replicas_list() :: list()
  @callback monitored_app() :: String.t()
  @callback phx_start_port() :: integer()
  @callback stdout_path(integer()) :: binary()
  @callback stderr_path(integer()) :: binary()
  @callback sname(integer()) :: String.t()
  @callback bin_path(integer()) :: String.t()
  @callback base_path() :: any()
  @callback new_path(integer()) :: binary()
  @callback current_path(integer()) :: binary()
  @callback previous_path(integer()) :: binary()

  @callback current_version_map(integer()) :: map()
  @callback set_current_version_map(integer(), map()) :: :ok
  @callback versions() :: list()
  @callback add_version(map()) :: :ok
  @callback ghosted_versions() :: list()
  @callback add_ghosted_version_map(map()) :: {:ok, list()}
end
