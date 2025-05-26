defmodule Foundation.Catalog.Adapter do
  @moduledoc """
  Behaviour that defines the catalog adapter callback
  """

  alias Foundation.Accounts
  alias Foundation.Catalog

  @type bin_service :: :current | :new

  @callback setup() :: :ok
  @callback setup(String.t()) :: :ok
  @callback cleanup(String.t() | nil) :: :ok
  @callback applications() :: list
  @callback create_sname(String.t()) :: String.t()
  @callback node_info(String.t() | node() | nil) :: Catalog.Node.t() | nil
  @callback stdout_path(String.t()) :: String.t() | nil
  @callback stderr_path(String.t()) :: String.t() | nil
  @callback bin_path(String.t(), bin_service()) :: String.t()
  @callback service_path(String.t()) :: String.t()
  @callback new_path(String.t()) :: String.t() | nil
  @callback current_path(String.t()) :: String.t() | nil
  @callback previous_path(String.t()) :: String.t() | nil
  @callback versions(String.t(), Keyword.t()) :: list()
  @callback add_version(map()) :: :ok
  @callback ghosted_versions(String.t()) :: list()
  @callback add_ghosted_version(map()) :: {:ok, list()}
  @callback add_user_session_token(Accounts.UserToken.t()) :: :ok
  @callback get_user_session_token_by_token(String.t()) :: Accounts.UserToken.t() | nil
  @callback config(String.t()) :: Catalog.Config.t()
  @callback config_update(String.t(), Catalog.Config.t()) :: {:ok, Catalog.Config.t()}
end
