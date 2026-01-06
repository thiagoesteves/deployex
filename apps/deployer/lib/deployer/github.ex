defmodule Deployer.Github do
  @moduledoc """
  This module contains deployex information about the latest release
  """

  alias Deployer.Github.Artifact
  alias Deployer.Github.Release

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @spec latest_release() :: Release.t()
  def latest_release, do: Release.latest_release()

  @spec download_artifact(url :: String.t(), token :: String.t()) ::
          {:ok, binary()} | {:error, any()}
  def download_artifact(url, token), do: Artifact.download_artifact(url, token)

  @spec subscribe_download_events() :: :ok | {:error, term}
  def subscribe_download_events, do: Artifact.subscribe_download_events()

  @spec stop_download_artifact(id :: binary()) :: :ok
  def stop_download_artifact(id), do: Artifact.stop_download_artifact(id)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
