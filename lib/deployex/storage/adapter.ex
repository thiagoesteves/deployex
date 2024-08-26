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
  @callback current_version_path(integer()) :: binary()
  @callback history_version_path :: binary()
  @callback ghosted_version_path :: binary()
end
