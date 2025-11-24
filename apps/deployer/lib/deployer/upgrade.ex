defmodule Deployer.Upgrade do
  @moduledoc """
   Provides functions for upgrading the application using appup files.
  """

  @behaviour Deployer.Upgrade.Adapter

  alias Deployer.Upgrade.Deployex

  ### ==========================================================================
  ### Hot upgrade functions for Managed applications
  ### ==========================================================================

  @doc """
  This function tries to connetc the respective node to the OTP distribution
  """
  @impl true
  @spec connect(node()) :: {:error, :not_connecting} | {:ok, node()}
  def connect(node), do: default().connect(node)

  @doc """
  This function acts like a hook for any modification before starting the app
  """
  @impl true
  @spec prepare_new_path(String.t(), String.t(), String.t(), String.t()) :: :ok
  def prepare_new_path(name, language, to_version, new_path),
    do: default().prepare_new_path(name, language, to_version, new_path)

  @doc """
  This function check the release package type
  """
  @impl true
  @spec check(Deployer.Upgrade.Check.t()) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def check(%Deployer.Upgrade.Check{} = data), do: default().check(data)

  @doc """
  This function triggers the hot code reloading process
  """
  @impl true
  @spec execute(Deployer.Upgrade.Execute.t()) :: :ok | {:error, any()}
  def execute(%Deployer.Upgrade.Execute{} = data), do: default().execute(data)

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

      iex> Deployer.Upgrade.deployex_check("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      {:ok, %Check{}}
  """
  @spec deployex_check(download_path :: String.t()) :: {:ok, Check.t()} | {:error, any()}
  def deployex_check(download_path), do: Deployex.check(download_path)

  @doc """
  Performs a hot upgrade of the DeployEx application itself.

  This function orchestrates a hot code upgrade by:
  1. Extracting the new release tarball to a temporary directory
  2. Checking if the release supports hot upgrade (via .appup files)
  3. Executing the hot upgrade sequence (unpack, relup, check, install)
  4. Skipping the `make_permanent` step (must be called separately for self-upgrades)

  ## Examples

      iex> Deployer.Upgrade.deployex_execute("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      :ok
  """
  @spec deployex_execute(download_path :: String.t()) :: :ok | {:error, any()}
  def deployex_execute(download_path), do: Deployex.execute(download_path)

  @doc """
  Makes a previously installed release permanent.

  This function marks the specified release version as permanent using the Erlang/OTP
  release handler. A permanent release will be the default version loaded on VM restart.

  For DeployEx self-upgrades, this function must be called separately after `hot_upgrade/1`
  succeeds. Calling it within the upgrade sequence causes process crashes.

  ## Examples

      iex> Deployer.Upgrade.deployex_make_permanent("/tmp/hotupgrade/deployex-0.8.1.tar.gz")
      :ok
      
      iex> Deployer.Upgrade.deployex_make_permanent("/path/to/invalid-release.tar.gz")
      {:error, {:no_such_release, '0.8.1'}}
  """
  @spec deployex_make_permanent(download_path :: String.t()) :: :ok | {:error, any()}
  def deployex_make_permanent(download_path), do: Deployex.make_permanent(download_path)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
