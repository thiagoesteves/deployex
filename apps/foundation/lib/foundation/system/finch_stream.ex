defmodule Foundation.System.FinchStream do
  @moduledoc false

  require Logger

  @type t :: %__MODULE__{
          url: String.t() | nil,
          file_path: String.t() | nil,
          headers: list(),
          status: non_neg_integer() | nil,
          size: non_neg_integer() | nil,
          processed: non_neg_integer() | nil,
          file_pid: pid() | nil,
          notify_callback: mfa(),
          keep_downloading_callback: mfa(),
          error: String.t() | nil
        }

  defstruct url: nil,
            file_path: nil,
            headers: [],
            status: nil,
            size: 0,
            processed: 0,
            file_pid: nil,
            notify_callback: nil,
            keep_downloading_callback: nil,
            error: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec download(url :: String.t(), headers :: list(), Keyword.t()) :: :ok | {:error, any()}
  def download(url, file_path, headers, options \\ []) do
    file_pid = Keyword.get(options, :file_pid) || File.open!(file_path, [:write, :binary])
    notify_callback = Keyword.get(options, :notify_callback)
    keep_downloading_callback = Keyword.get(options, :keep_downloading_callback)

    data = %__MODULE__{
      url: url,
      headers: headers,
      file_path: file_path,
      file_pid: file_pid,
      notify_callback: notify_callback,
      keep_downloading_callback: keep_downloading_callback
    }

    response = do_download(data)

    _ = File.close(file_pid)

    case response do
      {:ok, %__MODULE__{error: nil}} ->
        notify(data, :ok)
        :ok

      {:ok, %__MODULE__{error: reason}} ->
        response = {:error, reason}
        notify(data, response)
        response

      {:error, reason, _acc} ->
        response = {:error, reason}
        notify(data, response)
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
    if keep_downloading(params) do
      :ok = IO.binwrite(file_pid, data)
      new_params = %{params | processed: processed + byte_size(data), size: size}
      notify(new_params, :downloading)

      {:cont, new_params}
    else
      {:halt, %{params | error: "Download for file #{file_path} was cancelled"}}
    end
  end

  def notify(%__MODULE__{notify_callback: nil}, _status), do: :ok

  def notify(
        %__MODULE__{
          notify_callback: notify_callback,
          file_path: file_path,
          processed: processed,
          size: size
        },
        :downloading
      )
      when size > 0 do
    progress = Float.round(processed * 100 / size, 1)
    notify_callback.(file_path, {:downloading, progress})
  end

  def notify(%__MODULE__{notify_callback: notify_callback, file_path: file_path}, :ok) do
    notify_callback.(file_path, :ok)
  end

  def notify(%__MODULE__{notify_callback: notify_callback, file_path: file_path}, error) do
    notify_callback.(file_path, error)
  end

  def keep_downloading(%__MODULE__{keep_downloading_callback: nil}), do: true

  def keep_downloading(%__MODULE__{keep_downloading_callback: keep_downloading_callback}) do
    keep_downloading_callback.()
  end
end
