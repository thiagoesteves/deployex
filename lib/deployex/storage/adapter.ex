defmodule Deployex.Storage.Adapter do
  @moduledoc """
  Behaviour that defines the storage adapter callback
  """

  @callback setup() :: :ok
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

  @callback versions() :: list()
  @callback versions(integer()) :: list()
  @callback add_version(map()) :: :ok
  @callback ghosted_versions() :: list()
  @callback add_ghosted_version(map()) :: {:ok, list()}
  @callback add_user_session_token(Deployex.Accounts.UserToken.t()) :: :ok
  @callback get_user_session_token_by_token(String.t()) :: Deployex.Accounts.UserToken.t() | nil
  @callback config() :: Deployex.Storage.Config.t()
  @callback config_update(Deployex.Storage.Config.t()) :: {:ok, Deployex.Storage.Config.t()}
end
