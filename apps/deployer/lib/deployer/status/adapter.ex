defmodule Deployer.Status.Adapter do
  @moduledoc """
  Behaviour that defines the status adapter callback
  """

  alias Deployer.Release
  alias Foundation.Catalog

  @callback monitoring :: {:ok, list()} | {:error, :rescued}
  @callback monitored_app_name() :: String.t()
  @callback monitored_app_lang() :: String.t()
  @callback current_version(String.t()) :: String.t() | nil
  @callback current_version_map(String.t()) :: Catalog.Version.t()
  @callback list_installed_apps(String.t()) :: list()
  @callback subscribe() :: :ok
  @callback set_current_version_map(String.t(), Release.Version.t(), Keyword.t()) :: :ok
  @callback add_ghosted_version(Catalog.Version.t()) :: {:ok, list()}
  @callback ghosted_version_list :: list()
  @callback history_version_list :: list()
  @callback history_version_list(String.t()) :: list()
  @callback update(String.t()) :: :ok
  @callback set_mode(:automatic | :manual, String.t()) :: {:ok, map()}
end
