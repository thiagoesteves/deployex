defmodule Deployer.Github.Artifact do
  @moduledoc """
  This module provides a function to download a Github Artifact
  """

  use GenServer

  require Logger

  alias Foundation.Common
  alias Foundation.System.FinchStream
  alias Foundation.System.Zip

  @github_download_progress "deployex::github::download"
  @github_artifacts_table :deployex_github_table

  @type t :: %__MODULE__{
          id: String.t() | nil,
          owner: String.t() | nil,
          repo: String.t() | nil,
          headers: list(),
          rund_id: String.t() | nil,
          artifact_id: String.t() | nil,
          artifact_name: String.t() | nil,
          artifact_path: String.t() | nil,
          url: String.t() | nil,
          download_url: String.t() | nil,
          downloads_path: String.t() | nil,
          token: String.t() | nil,
          file_path: String.t() | nil,
          request_pid: pid()
        }

  defstruct id: nil,
            owner: nil,
            repo: nil,
            headers: [],
            rund_id: nil,
            artifact_id: nil,
            artifact_name: nil,
            artifact_path: nil,
            url: nil,
            download_url: nil,
            downloads_path: nil,
            token: nil,
            file_path: nil,
            request_pid: nil

  ### ==========================================================================
  ### Callback GenServer functions
  ### ==========================================================================

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    :ets.new(@github_artifacts_table, [:set, :public, :named_table])

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:download_artifact, data}, state) do
    do_download_artifact(data)

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @spec download_artifact(url :: String.t(), token :: String.t()) ::
          {:ok, binary()} | {:error, any()}
  def download_artifact(url, token) do
    id = Common.uuid4()

    :ok =
      GenServer.cast(
        __MODULE__,
        {:download_artifact, %__MODULE__{id: id, url: url, token: token, request_pid: self()}}
      )

    {:ok, id}
  end

  @spec subscribe_download_events() :: :ok | {:error, term}
  def subscribe_download_events do
    Phoenix.PubSub.subscribe(Deployer.PubSub, @github_download_progress)
  end

  @spec stop_download_artifact(id :: binary()) :: :ok
  def stop_download_artifact(id) do
    _ = :ets.insert(@github_artifacts_table, {id, :stop})
    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp do_download_artifact(data) do
    Logger.info("Start Downloading file from: #{data.url} with id: #{data.id}")

    data = %{data | downloads_path: "#{:code.priv_dir(:deployer)}/static/downloads/#{data.id}"}

    with {:ok, %__MODULE__{} = data} <- parse_github_actions_url(data, data.url, data.token),
         {:ok, %__MODULE__{} = data} <- get_artifact_name(data),
         {:ok, %__MODULE__{} = data} <- download_file(data),
         {:ok, _} <- Zip.unzip(~c"#{data.file_path}", [{:cwd, ~c"#{data.downloads_path}"}]) do
      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        @github_download_progress,
        {:github_download_artifact, Node.self(), data, :ok}
      )

      Logger.info("File #{data.file_path} Downloaded with success")
    else
      error ->
        Phoenix.PubSub.broadcast(
          Deployer.PubSub,
          @github_download_progress,
          {:github_download_artifact, Node.self(), data, error}
        )

        Logger.error(
          "Error while trying to download url: #{data.url} id: #{data.id}, reason: #{inspect(error)}"
        )
    end

    :ets.delete(@github_artifacts_table, data.id)
  end

  defp parse_github_actions_url(%__MODULE__{} = data, github_url, token) do
    case String.split(github_url, ["https://github.com", "/"], trim: true) do
      [owner, repo, "actions", "runs", run_id, "artifacts", artifact_id] ->
        headers = build_github_headers(token)

        {:ok,
         %{
           data
           | owner: owner,
             repo: repo,
             headers: headers,
             rund_id: run_id,
             artifact_id: artifact_id,
             url: github_url,
             token: token
         }}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp get_artifact_name(
         %__MODULE__{owner: owner, repo: repo, artifact_id: artifact_id, headers: headers} =
           github_data
       ) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/actions/artifacts/#{artifact_id}"

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           :get |> Finch.build(url, headers, []) |> Finch.request(Deployer.Finch),
         {:ok, %{"name" => name, "archive_download_url" => download_url}} <- Jason.decode(body) do
      {:ok, %{github_data | artifact_name: name, download_url: download_url}}
    end
  end

  defp download_file(
         %__MODULE__{
           headers: headers,
           artifact_name: artifact_name,
           download_url: download_url,
           downloads_path: downloads_path,
           id: id
         } = params
       ) do
    # Cleanup and preparation
    File.mkdir_p!(downloads_path)
    file_path = "#{downloads_path}/#{artifact_name}.zip"
    artifact_path = "#{downloads_path}/#{artifact_name}"

    new_params = %{params | file_path: file_path, artifact_path: artifact_path}

    :ets.insert(@github_artifacts_table, {id, :run})

    notify_callback = fn
      _file_path, :ok ->
        # Skip the initial :ok message.
        # This module still needs to unzip the download before notifying
        # that the download is fully completed.
        :ok

      _file_path, result ->
        Phoenix.PubSub.broadcast(
          Deployer.PubSub,
          @github_download_progress,
          {:github_download_artifact, Node.self(), new_params, result}
        )
    end

    keep_downloading_callback = fn ->
      [{_, status}] = :ets.lookup(@github_artifacts_table, id)
      Process.alive?(params.request_pid) and status == :run
    end

    with :ok <-
           FinchStream.download(download_url, file_path, headers,
             notify_callback: notify_callback,
             keep_downloading_callback: keep_downloading_callback
           ) do
      {:ok, new_params}
    end
  end

  defp build_github_headers(token) when token != "" and token != nil do
    [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{token}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end

  defp build_github_headers(_token) do
    [
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end
end
