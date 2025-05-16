defmodule Foundation.Catalog.Adapter do
  @moduledoc """
  Behaviour that defines the catalog adapter callback
  """

  @type bin_service :: :current | :new

  @callback setup() :: :ok
  @callback setup(node()) :: :ok | {:error, :invalid_node}
  @callback cleanup(node() | nil) :: :ok | {:error, :invalid_node}
  @callback replicas() :: integer()
  @callback replicas_list() :: list()
  @callback monitored_app_name() :: String.t()
  @callback monitored_app_lang() :: String.t()
  @callback monitored_app_env() :: list()
  @callback monitored_app_start_port() :: integer()
  @callback node_info(String.t() | node()) :: Foundation.Catalog.Node.t() | nil
  @callback node_info_from_sname(String.t()) :: Foundation.Catalog.Node.t() | nil
  @callback stdout_path(node()) :: String.t() | nil
  @callback stderr_path(node()) :: String.t() | nil
  @callback bin_path(node(), String.t(), bin_service()) :: String.t()
  @callback base_path() :: any()
  @callback new_path(node()) :: String.t() | nil
  @callback current_path(node()) :: String.t() | nil
  @callback previous_path(node()) :: String.t() | nil
  @callback versions() :: list()
  @callback versions(node()) :: list()
  @callback add_version(map()) :: :ok
  @callback ghosted_versions() :: list()
  @callback add_ghosted_version(map()) :: {:ok, list()}
  @callback add_user_session_token(Foundation.Accounts.UserToken.t()) :: :ok
  @callback get_user_session_token_by_token(String.t()) :: Foundation.Accounts.UserToken.t() | nil
  @callback config() :: Foundation.Catalog.Config.t()
  @callback config_update(Foundation.Catalog.Config.t()) :: {:ok, Foundation.Catalog.Config.t()}
end
