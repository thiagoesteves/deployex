defmodule Foundation.System.FinchStream do
  @moduledoc """
  Downloads files using Finch with streaming support.

  ## Usage

  Basic download without callbacks:

      FinchStream.download(url, file_path, headers)

  ## Callbacks

  You can provide optional callbacks to track progress and control the download.

  ### handle_progress

  A function that receives progress updates during the download. It will be called with:
  - `file_path` - The path of the file being downloaded
  - `status` - One of:
    - `{:downloading, progress}` - Progress as a float (0.0 to 100.0)
    - `:ok` - Download completed successfully
    - `{:error, reason}` - Download failed

  Example:

      handle_progress = fn file_path, status ->
        case status do
          {:downloading, progress} ->
            IO.puts("Downloading \#{file_path}: \#{progress}%")
          
          :ok ->
            IO.puts("✓ Completed: \#{file_path}")
          
          {:error, reason} ->
            IO.puts("✗ Failed: \#{file_path} - \#{inspect(reason)}")
        end
      end

      FinchStream.download(url, file_path, headers, handle_progress: handle_progress)

  ### handle_continue

  A function that determines whether the download should continue. Called before 
  processing each data chunk. Return `true` to continue, `false` to cancel.

  Example:

      handle_continue = fn ->
        # Cancel if user requested it
        !Process.get(:cancel_download, false)
      end

      FinchStream.download(url, file_path, headers, handle_continue: handle_continue)

  ## Full Example

      defmodule MyApp.Downloader do
        def download_with_tracking(url, file_path) do
          # Track progress in process dictionary
          Process.put(:download_progress, 0)
          
          handle_progress = fn _file_path, status ->
            case status do
              {:downloading, progress} ->
                Process.put(:download_progress, progress)
                Phoenix.PubSub.broadcast(
                  MyApp.PubSub,
                  "downloads",
                  {:progress, file_path, progress}
                )
              
              :ok ->
                Logger.info("Download completed: \#{file_path}")
              
              {:error, reason} ->
                Logger.error("Download failed: \#{file_path} - \#{inspect(reason)}")
            end
          end
          
          handle_continue = fn ->
            # Stop if cancelled or if progress hasn't changed in too long
            !Process.get(:cancel_download, false)
          end
          
          Foundation.System.FinchStream.download(
            url,
            file_path,
            [],
            handle_progress: handle_progress,
            handle_continue: handle_continue
          )
        end
        
        def cancel_download do
          Process.put(:cancel_download, true)
        end
      end
  """

  require Logger

  @type t :: %__MODULE__{
          url: String.t() | nil,
          file_path: String.t() | nil,
          headers: list(),
          status: non_neg_integer() | nil,
          size: non_neg_integer() | nil,
          processed: non_neg_integer() | nil,
          file_pid: pid() | nil,
          handle_progress: mfa(),
          handle_continue: mfa(),
          error: String.t() | nil
        }

  defstruct url: nil,
            file_path: nil,
            headers: [],
            status: nil,
            size: 0,
            processed: 0,
            file_pid: nil,
            handle_progress: nil,
            handle_continue: nil,
            error: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec download(url :: String.t(), headers :: list(), Keyword.t()) :: :ok | {:error, any()}
  def download(url, file_path, headers, options \\ []) do
    file_pid = Keyword.get(options, :file_pid) || File.open!(file_path, [:write, :binary])
    handle_progress = Keyword.get(options, :handle_progress)
    handle_continue = Keyword.get(options, :handle_continue)

    data = %__MODULE__{
      url: url,
      headers: headers,
      file_path: file_path,
      file_pid: file_pid,
      handle_progress: handle_progress,
      handle_continue: handle_continue
    }

    response = do_download(data)

    _ = File.close(file_pid)

    case response do
      {:ok, %__MODULE__{error: nil}} ->
        do_handle_progress(data, :ok)
        :ok

      {:ok, %__MODULE__{error: reason}} ->
        response = {:error, reason}
        do_handle_progress(data, response)
        response

      {:error, reason, _acc} ->
        response = {:error, reason}
        do_handle_progress(data, response)
        response
    end
  end

  ### ==========================================================================
  ### Private APIs
  ### ==========================================================================
  defp do_download(%__MODULE__{} = params) do
    Finch.build(:get, params.url, params.headers)
    |> Finch.stream_while(Deployer.Finch, params, fn
      {:status, status}, acc ->
        {:cont, %{acc | status: status}}

      # - when we receive 302, we put the "location" header in the "acc"
      # - when we receive a 200, we put the "content-length" in the "acc",
      {:headers, headers}, acc ->
        handle_headers(headers, acc)

      # Write the received chunk into the file
      {:data, data}, acc ->
        handle_data(data, acc)
    end)
  end

  defp handle_headers(headers, %__MODULE__{status: status} = params)
       when status in [301, 302, 303, 307, 308] do
    case Enum.find(headers, &(elem(&1, 0) == "location")) do
      nil ->
        {:halt, %{params | error: "Error during redirection"}}

      {"location", location} ->
        # recursion
        case do_download(%{params | url: location, headers: headers}) do
          {:ok, _} ->
            {:cont, params}

          {:error, reason, params} ->
            {:halt, %{params | error: "Error downloading, reason: #{inspect(reason)}"}}
        end
    end
  end

  defp handle_headers(headers, %__MODULE__{status: 200} = acc) do
    case Enum.find(headers, &(elem(&1, 0) == "content-length")) do
      nil ->
        {:cont, %{acc | size: 0, processed: 0}}

      {"content-length", size} ->
        {:cont, %{acc | size: String.to_integer(size), processed: 0}}
    end
  end

  defp handle_headers(_, params) do
    {:halt, %{params | error: "Bad handler status"}}
  end

  defp handle_data(
         data,
         %__MODULE__{
           processed: processed,
           size: size,
           file_path: file_path,
           file_pid: file_pid
         } = params
       ) do
    if do_handle_continue(params) do
      :ok = IO.binwrite(file_pid, data)
      new_params = %{params | processed: processed + byte_size(data), size: size}
      do_handle_progress(new_params, :downloading)

      {:cont, new_params}
    else
      {:halt, %{params | error: "Download for file #{file_path} was cancelled"}}
    end
  end

  defp do_handle_progress(%__MODULE__{handle_progress: nil}, _status), do: :ok

  defp do_handle_progress(
         %__MODULE__{
           handle_progress: handle_progress,
           file_path: file_path,
           processed: processed,
           size: size
         },
         :downloading
       )
       when size > 0 do
    progress = Float.round(processed * 100 / size, 1)
    handle_progress.(file_path, {:downloading, progress})
  end

  defp do_handle_progress(
         %__MODULE__{handle_progress: handle_progress, file_path: file_path},
         :ok
       ) do
    handle_progress.(file_path, :ok)
  end

  defp do_handle_progress(
         %__MODULE__{handle_progress: handle_progress, file_path: file_path},
         error
       ) do
    handle_progress.(file_path, error)
  end

  def do_handle_continue(%__MODULE__{handle_continue: nil}), do: true

  def do_handle_continue(%__MODULE__{handle_continue: handle_continue}) do
    handle_continue.()
  end
end
