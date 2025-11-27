defmodule Deployer.Github.Artifacts do
  @moduledoc """
  This module contains deployex information about the latest release
  """

  use GenServer

  require Logger

  alias Foundation.FinchStream

  @github_download_progress "deployex::github::download"

  ### ==========================================================================
  ### Callback GenServer functions
  ### ==========================================================================
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(_args) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:download_artifact, url, token}, state) do
    do_download_artifact(url, token)

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @spec download_artifact(url :: String.t(), token :: String.t()) :: :ok
  def download_artifact(module \\ __MODULE__, url, token) do
    GenServer.cast(module, {:download_artifact, url, token})
  end

  def subscribe_download_events do
    Phoenix.PubSub.subscribe(Deployer.PubSub, @github_download_progress)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  def do_download_artifact(url, token) do
    Logger.info("Start Downloading file from: #{url}")

    with {:ok, github_data} <- parse_github_actions_url(url, token),
         {:ok, github_data} <- get_artifact_name(github_data),
         {:ok, github_data} <- download_file(github_data) do
      Logger.info("File #{github_data.file_path} Downloaded with success")
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_github_actions_url(github_url, token) do
    case String.split(github_url, ["https://github.com", "/"], trim: true) do
      [owner, repo, "actions", "runs", run_id, "artifacts", artifact_id] ->
        headers = build_github_headers(token)

        {:ok,
         %{
           owner: owner,
           repo: repo,
           headers: headers,
           rund_id: run_id,
           artifact_id: artifact_id,
           artifact_name: nil,
           url: github_url,
           download_url: nil,
           token: token,
           file_path: nil
         }}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp get_artifact_name(
         %{owner: owner, repo: repo, artifact_id: artifact_id, headers: headers} = github_data
       ) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/actions/artifacts/#{artifact_id}"

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           :get |> Finch.build(url, headers, []) |> Finch.request(Deployer.Finch),
         {:ok, %{"name" => name, "archive_download_url" => download_url}} <- Jason.decode(body) do
      {:ok, %{github_data | artifact_name: name, download_url: download_url}}
    end
  end

  defp download_file(
         %{headers: headers, artifact_name: artifact_name, download_url: download_url} = params
       ) do
    file_path = "/tmp/download/#{artifact_name}.zip"

    File.rm(file_path)

    status_fun = fn file_path, status, progress ->
      Logger.info("#{progress}%")

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        @github_download_progress,
        {:github_download_progress, Node.self(), file_path, status, progress}
      )
    end

    :ok = FinchStream.download(download_url, file_path, headers, status_fun: status_fun)

    {:ok, %{params | file_path: file_path}}
  end

  def build_github_headers(token) when token != "" and token != nil do
    [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{token}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end

  def build_github_headers(_token) do
    [
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end
end
