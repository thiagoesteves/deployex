defmodule Deployer.Upgrade do
  @moduledoc """
   Provides functions for upgrading the application using appup files.

  ## References

  - Appup Files Generation: [Distillery GitHub](https://github.com/bitwalker/distillery)
  - Relup and Release Installations: [Relx GitHub](https://github.com/erlware/relx/blob/main/priv/templates/install_upgrade_escript)
  - Updating the Config: [Castle GitHub](https://github.com/ausimian/castle/blob/main/lib/castle.ex)
  """

  @behaviour Deployer.Upgrade.Adapter

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  This function tries to connetc the respective node to the OTP distribution
  """
  @impl true
  @spec connect(node()) :: {:error, :not_connecting} | {:ok, node()}
  def connect(node), do: default().connect(node)

  @doc """
  This function check the release package type
  """
  @impl true
  @spec check(
          node(),
          String.t(),
          String.t(),
          binary(),
          binary() | charlist() | nil,
          binary() | charlist()
        ) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def check(node, app_name, app_lang, download_path, from_version, to_version) do
    default().check(node, app_name, app_lang, download_path, from_version, to_version)
  end

  @doc """
  This function triggers the hot code reloading process
  """
  @impl true
  @spec execute(
          node(),
          String.t(),
          String.t(),
          binary() | charlist() | nil,
          binary() | charlist() | nil
        ) ::
          :ok | {:error, any()}
  def execute(node, app_name, app_lang, from_version, to_version) do
    default().execute(node, app_name, app_lang, from_version, to_version)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
