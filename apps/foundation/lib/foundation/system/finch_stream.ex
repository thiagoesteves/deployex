defmodule Foundation.System.FinchStream do
  @moduledoc """
  Downloads files using Finch with streaming support.

  References:
  https://dev.to/ndrean/notes-on-streaming-downloads-with-progress-in-elixir-4nk7

  ## Usage

  Basic download without callbacks:

      FinchStream.download(url, file_path, headers)

  ## Callbacks

  Optional callbacks track progress and control the download.
  Both are `{module, function, args}` and are applied rather than called.

  A download can run for as long as the transfer takes, which is long enough for a hot
  upgrade to replace the module that started it. A function value captured by the previous
  version of that module does not survive being replaced and raises `BadFunctionError` when
  applied, so the callbacks are named functions reached through their module, which resolves
  to whatever is loaded at the time.

  ### handle_progress

  Applied with the stored args followed by:
  - `file_path` - The path of the file being downloaded
  - `status` - One of:
    - `{:downloading, progress}` - Progress as a float (0.0 to 100.0)
    - `:ok` - Download completed successfully
    - `{:error, reason}` - Download failed

  ### handle_continue

  Applied with the stored args, before processing each data chunk.
  Return `true` to continue, `false` to cancel.

  ## Full Example

      defmodule MyApp.Downloader do
        def download_with_tracking(url, file_path) do
          Foundation.System.FinchStream.download(
            url,
            file_path,
            [],
            handle_progress: {__MODULE__, :report_progress, [self()]},
            handle_continue: {__MODULE__, :keep_going?, [self()]}
          )
        end

        def report_progress(owner, file_path, {:downloading, progress}) do
          Phoenix.PubSub.broadcast(MyApp.PubSub, "downloads", {:progress, file_path, progress})
          send(owner, {:progress, progress})
        end

        def report_progress(_owner, file_path, :ok) do
          Logger.info("Download completed: \#{file_path}")
        end

        def report_progress(_owner, file_path, {:error, reason}) do
          Logger.error("Download failed: \#{file_path} - \#{inspect(reason)}")
        end

        def keep_going?(owner), do: Process.alive?(owner)
      end
  """

  @typedoc """
  A callback to apply, carrying the arguments to apply it with, which the stream appends to.

  Not `mfa()`, whose third element is an arity rather than an argument list.
  """
  @type callback :: {module(), atom(), list()}

  @type t :: %__MODULE__{
          url: String.t() | nil,
          file_path: String.t() | nil,
          headers: list(),
          status: non_neg_integer() | nil,
          size: non_neg_integer() | nil,
          processed: non_neg_integer() | nil,
          file_pid: pid() | nil,
          handle_progress: callback() | nil,
          handle_continue: callback() | nil,
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
    apply_callback(handle_progress, [file_path, {:downloading, progress}])
  end

  defp do_handle_progress(
         %__MODULE__{handle_progress: handle_progress, file_path: file_path},
         :ok
       ) do
    apply_callback(handle_progress, [file_path, :ok])
  end

  defp do_handle_progress(
         %__MODULE__{handle_progress: handle_progress, file_path: file_path},
         error
       ) do
    apply_callback(handle_progress, [file_path, error])
  end

  def do_handle_continue(%__MODULE__{handle_continue: nil}), do: true

  def do_handle_continue(%__MODULE__{handle_continue: handle_continue}) do
    apply_callback(handle_continue, [])
  end

  # Applied through the module rather than called as a value, so it resolves against the
  # code loaded now and not the version that started the download
  defp apply_callback({module, function, args}, extra_args) do
    apply(module, function, args ++ extra_args)
  end
end
