defmodule Deployex.Upgrade do
  @moduledoc """
  This module will provide module abstraction
  """

  @behaviour Deployex.Upgrade.Adapter

  def default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  This function tries to connetc the respective instance to the OTP distribution
  """
  @impl true
  @spec connect(integer()) :: {:error, :not_connecting} | {:ok, atom()}
  def connect(instance), do: default().connect(instance)

  @doc """
  This function check the release package type
  """
  @impl true
  @spec check(integer(), binary(), binary() | charlist() | nil, binary() | charlist()) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def check(instance, download_path, from_version, to_version) do
    default().check(instance, download_path, from_version, to_version)
  end

  @doc """
  This function triggers the hot code reloading process
  """
  @impl true
  @spec execute(integer(), binary() | charlist() | nil, binary() | charlist() | nil) ::
          :ok | {:error, any()}
  def execute(instance, from_version, to_version) do
    default().execute(instance, from_version, to_version)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
