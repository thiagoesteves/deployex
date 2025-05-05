defmodule Foundation.Catalog.Adapter do
  @moduledoc """
  Behaviour that defines the catalog adapter callback
  """

  @type bin_service :: :current | :new

  @callback setup() :: :ok
  @callback replicas() :: integer()
  @callback replicas_list() :: list()
  @callback instance_list() :: list()
  @callback monitored_app_name() :: String.t()
  @callback monitored_app_lang() :: String.t()
  @callback monitored_app_env() :: list()
  @callback monitored_app_start_port() :: integer()
  @callback expected_nodes() :: list()
  @callback monitored_nodes() :: list()
  @callback parse_node_name(String.t() | atom()) :: map() | nil
  @callback stdout_path(integer()) :: binary()
  @callback stderr_path(integer()) :: binary()
  @callback sname(integer()) :: String.t()
  @callback bin_path(integer(), String.t(), bin_service()) :: String.t()
  @callback base_path() :: any()
  @callback new_path(integer()) :: binary()
  @callback current_path(integer()) :: binary()
  @callback previous_path(integer()) :: binary()

  @callback versions() :: list()
  @callback versions(integer()) :: list()
  @callback add_version(map()) :: :ok
  @callback ghosted_versions() :: list()
  @callback add_ghosted_version(map()) :: {:ok, list()}
  @callback add_user_session_token(Foundation.Accounts.UserToken.t()) :: :ok
  @callback get_user_session_token_by_token(String.t()) :: Foundation.Accounts.UserToken.t() | nil
  @callback config() :: Foundation.Catalog.Config.t()
  @callback config_update(Foundation.Catalog.Config.t()) :: {:ok, Foundation.Catalog.Config.t()}
end
