defmodule Deployer.HotUpgrade do
  @moduledoc """
   Provides functions for upgrading the application using appup files.
  """

  @behaviour Deployer.HotUpgrade.Adapter

  alias Deployer.HotUpgrade.Check
  alias Deployer.HotUpgrade.Deployex
  alias Deployer.HotUpgrade.Execute

  ### ==========================================================================
  ### Hot upgrade functions for Managed applications
  ### ==========================================================================

  @doc """
  This function tries to connetc the respective node to the OTP distribution
  """
  @impl true
  @spec connect(node :: node()) :: {:error, :not_connecting} | {:ok, node()}
  def connect(node), do: default().connect(node)

  @doc """
  This function acts like a hook for any modification before starting the app
  """
  @impl true
  @spec prepare_new_path(
          name :: String.t(),
          language :: String.t(),
          to_version :: String.t(),
          new_path :: String.t()
        ) :: :ok
  def prepare_new_path(name, language, to_version, new_path),
    do: default().prepare_new_path(name, language, to_version, new_path)

  @doc """
  This function check the release package type
  """
  @impl true
  @spec check(data :: Check.t()) :: {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def check(%Check{} = data), do: default().check(data)

  @doc """
  This function triggers the hot code reloading process
  """
  @impl true
  @spec execute(data :: Execute.t()) :: :ok | {:error, any()}
  def execute(%Execute{} = data), do: default().execute(data)

  @doc """
  This function subscribes to hotupgrade events
  """
  @impl true
  @spec subscribe_events() :: :ok
  def subscribe_events, do: default().subscribe_events()

  ### ==========================================================================
  ### Hot upgrade functions for DeployEx
  ### ==========================================================================

  @doc """
  Performs a hot upgrade check for deployex only

  This function orchestrates a hot code upgrade by:
  1. Extracting the new release tarball to a temporary directory
  2. Checking if the release supports hot upgrade (via .appup files)

  ## Examples

      iex> Deployer.HotUpgrade.deployex_check("/tmp/hotupgrade/deployex-0.9.0.tar.gz")
      {:ok, %Check{}}
  """
  @spec deployex_check(download_path :: String.t()) :: {:ok, Check.t()} | {:error, any()}
  def deployex_check(download_path), do: Deployex.check(download_path)

  @doc """
  Performs a hot upgrade of the DeployEx application itself.

  This function orchestrates a hot code upgrade by:
  1. Extracting the new release tarball to a temporary directory
  2. Checking if the release supports hot upgrade (via .appup files)
  3. Executing the hot upgrade sequence (unpack, relup, check, install, make_permanent)
  4. Using options, you can run this function syc or async, as well as make_permanent version
     async

  ## Examples

      iex> Deployer.HotUpgrade.deployex_execute("/tmp/hotupgrade/deployex-0.9.0.tar.gz")
      :ok
  """
  @spec deployex_execute(download_path :: String.t(), options :: Keyword.t()) ::
          :ok | {:error, any()}
  def deployex_execute(download_path, options \\ []), do: Deployex.execute(download_path, options)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
