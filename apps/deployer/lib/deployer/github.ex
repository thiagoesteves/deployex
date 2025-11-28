defmodule Deployer.Github do
  @moduledoc """
  This module contains deployex information about the latest release
  """

  alias Deployer.Github.Artifact
  alias Deployer.Github.Release

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @spec latest_release() :: {:ok, Release.t()}
  def latest_release, do: Release.latest_release()

  @spec download_artifact(url :: String.t(), token :: String.t()) :: :ok | {:error, any()}
  def download_artifact(url, token), do: Artifact.download_artifact(url, token)

  @spec subscribe_download_events() :: :ok | {:error, term}
  def subscribe_download_events, do: Artifact.subscribe_download_events()

  @spec stop_download_artifact(url :: String.t()) :: :ok
  def stop_download_artifact(url), do: Artifact.stop_download_artifact(url)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
