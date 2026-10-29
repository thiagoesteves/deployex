defmodule DeployexWeb.AgentApi.Logs do
  @moduledoc """
  Builds the agent API view of the logs that DeployEx keeps for each instance of a monitored
  app, also an instance that no longer runs.

  Each entry is one line, with the time DeployEx read it.
  """

  alias DeployexWeb.AgentApi.Apps
  alias Sentinel.Logs
  alias Sentinel.Logs.Message

  @types ["stdout", "stderr"]
  @default_limit 1_000
  @max_limit 10_000

  # A + in a query string decodes to a space, so the detail names its encoding
  @invalid_since {:error,
                  {:invalid,
                   "since must be an ISO 8601 time with an offset, like 2026-10-23T12:00:00Z (write + as %2B)"}}
  @invalid_limit {:error, {:invalid, "limit must be an integer from 1 to #{@max_limit}"}}

  @type entry :: %{timestamp: String.t(), line: String.t()}
  @type history :: %{logs: [entry()], truncated: boolean()}
  @type error :: {:error, :not_found | :unavailable | {:invalid, String.t()}}

  @doc """
  Returns the newest `limit` lines of one instance and log type at or after `since`, oldest
  first. Without `since`, it reads every line that DeployEx still keeps. `truncated` is true
  when older lines did not fit in `limit`.
  """
  @spec history(
          name :: String.t(),
          sname :: term(),
          type :: term(),
          since :: term(),
          limit :: term()
        ) :: {:ok, history()} | error()
  def history(name, sname, type, since, limit) do
    with :ok <- check(name, sname, type),
         {:ok, since} <- since(since),
         {:ok, limit} <- limit(limit) do
      entries =
        sname
        |> Logs.list_data_by_sname_log_type(type, from: minutes_back(since))
        |> Enum.filter(&(is_nil(since) or &1.timestamp >= since))
        |> Enum.flat_map(&entries/1)

      dropped = max(length(entries) - limit, 0)
      {:ok, %{logs: Enum.drop(entries, dropped), truncated: dropped > 0}}
    end
  end

  @doc """
  Subscribes the caller to the new lines of one instance and log type. The caller then
  receives `{:logs_new_data, sname, type, message}`.
  """
  @spec subscribe(sname :: String.t(), type :: String.t()) :: :ok | error()
  def subscribe(sname, type) do
    with :ok <- check(app_name(sname), sname, type) do
      Logs.subscribe_for_new_logs(sname, type)
    end
  end

  @doc """
  Splits one stored message into its lines.
  """
  @spec entries(message :: Message.t()) :: [entry()]
  def entries(%Message{timestamp: timestamp, log: log}) do
    at = timestamp |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()

    # tail can split a multibyte character between two messages, and JSON needs UTF-8
    log
    |> String.replace_invalid()
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.map(&%{timestamp: at, line: &1})
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp check(name, sname, type) do
    with {:ok, _app} <- Apps.find(name),
         :ok <- type(type),
         :ok <- sname(sname) do
      stored(name, sname)
    end
  end

  # Checked before the log store makes an atom of the sname
  defp stored(name, sname) do
    if app_name(sname) == name and sname in Logs.list_active_snames(),
      do: :ok,
      else: {:error, :not_found}
  end

  defp type(type) when type in @types, do: :ok
  defp type(_type), do: {:error, {:invalid, "type must be stdout or stderr"}}

  defp sname(sname) when is_binary(sname), do: :ok
  defp sname(_sname), do: {:error, {:invalid, "sname is required"}}

  # A sname is the app name and a suffix, as Foundation.Catalog.create_sname/1 makes it
  defp app_name(sname) do
    case String.split(sname, "-") do
      [name, _suffix] -> name
      _other -> nil
    end
  end

  defp since(nil), do: {:ok, nil}

  defp since(since) when is_binary(since) do
    case DateTime.from_iso8601(since) do
      {:ok, at, _offset} -> {:ok, DateTime.to_unix(at, :millisecond)}
      {:error, _reason} -> @invalid_since
    end
  end

  defp since(_since), do: @invalid_since

  defp limit(nil), do: {:ok, @default_limit}

  defp limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {limit, ""} when limit in 1..@max_limit -> {:ok, limit}
      _other -> @invalid_limit
    end
  end

  defp limit(_limit), do: @invalid_limit

  # The log store reads one key per minute. It reads the clock again, so one more minute
  # keeps the minute of since when the minute changes between the two reads
  defp minutes_back(nil), do: kept_minutes()

  defp minutes_back(since) do
    minutes = div(System.os_time(:millisecond), 60_000) - div(since, 60_000) + 1
    minutes |> max(0) |> min(kept_minutes())
  end

  # The log store prunes a minute once it is older than the retention
  defp kept_minutes,
    do: div(Application.get_env(:foundation, :logs_retention_time_ms) || 0, 60_000) + 1
end
