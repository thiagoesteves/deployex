defmodule Foundation.FinchStream do
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
          status_fun: mfa(),
          error: String.t() | nil
        }

  defstruct url: nil,
            file_path: nil,
            headers: [],
            status: nil,
            size: 0,
            processed: 0,
            file_pid: nil,
            status_fun: nil,
            error: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  def download(url, file_path, headers, options \\ []) do
    file_pid = Keyword.get(options, :file_pid) || File.open!(file_path, [:write, :binary])
    status_fun = Keyword.get(options, :status_fun)

    response =
      do_download(%__MODULE__{
        url: url,
        headers: headers,
        file_path: file_path,
        file_pid: file_pid,
        status_fun: status_fun
      })

    _ = File.close(file_pid)

    case response do
      {:ok, %__MODULE__{error: reason}} when reason != nil ->
        {:error, reason}

      {:ok, %__MODULE__{}} ->
        :ok

      error ->
        error
    end
  end

  def do_download(%__MODULE__{} = params) do
    # the HTTP stream request
    Finch.build(:get, params.url, params.headers)
    |> Finch.stream_while(Deployer.Finch, params, fn
      {:status, status}, acc ->
        {:cont, %{acc | status: status}}

      # - when we receive 302, we put the "location" header in the "acc"
      # - when we receive a 200, we put the "content-length" in the "acc",
      {:headers, headers}, acc ->
        handle_headers(headers, acc)

      # Write the chunk into the file and print out the current progress.
      {:data, data}, acc ->
        handle_data(data, acc)
    end)
  end

  ### ==========================================================================
  ### Private APIs
  ### ==========================================================================

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

          {:error, reason} ->
            {:halt, %{params | error: "Error downloading, reason #{inspect(reason)}"}}
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

  defp handle_headers(_, _acc), do: {:halt, :bad_status}

  defp handle_data(
         data,
         %__MODULE__{
           processed: processed,
           size: size,
           file_path: file_path,
           file_pid: file_pid,
           status_fun: status_fun
         } = params
       ) do
    case IO.binwrite(file_pid, data) do
      :ok ->
        processed = processed + byte_size(data)

        if status_fun != nil and size > 0 do
          progress = Float.round(processed * 100 / size, 1)
          status_fun.(file_path, :downloading, progress)
        end

        {:cont, %{params | processed: processed, size: size}}

      {:error, reason} ->
        {:halt, %{params | error: "Error writing file #{file_path}, reason #{inspect(reason)}"}}
    end
  end
end
