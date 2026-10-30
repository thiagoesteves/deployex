defmodule DeployexWeb.LogsExport do
  @moduledoc """
  The log lines of an export: what the Logs page or a dock logs tab selects (sources, streams, the last
  minutes and the text filter), read in full from the log server and this host's events, oldest first.
  A line is written as plain text (`.log`) or as one JSON object (`.jsonl`).
  """

  alias DeployexWeb.RecentEvents
  alias Foundation.Notifications.Recent
  alias Sentinel.Logs

  @types ["stdout", "stderr"]
  # The longest History range, a week
  @max_minutes 10_080

  @type line :: %{at: DateTime.t(), source: String.t(), stream: String.t(), text: String.t()}

  @doc """
  Returns the params of an export link, for `/logs/export`. The time window is `minutes`, the last minutes
  at export time, or `since`, unix seconds, for a live view that shows the lines since it opened.
  """
  @spec params(map()) :: keyword()
  def params(selection) do
    Enum.reject(
      [
        source: Enum.join(selection.sources, ","),
        stream: Enum.join(selection.types, ","),
        minutes: selection[:minutes],
        since: selection[:since],
        filter: selection[:filter]
      ],
      fn {_key, value} -> value in ["", nil] end
    )
  end

  @doc """
  Reads the lines of the export the query params ask for. Only the sources this host has are read, and
  the time window stays within a week.
  """
  @spec lines(map()) :: [line()]
  def lines(params) do
    sources = known_sources(list(params["source"]))
    types = Enum.filter(list(params["stream"]), &(&1 in @types))
    types = if types == [], do: @types, else: types
    minutes = minutes(params)
    filter = String.downcase(params["filter"] || "")

    (log_lines(sources -- ["events"], types, minutes) ++ event_lines(sources, minutes))
    |> Enum.filter(&holds?(&1, filter))
    |> Enum.sort_by(&DateTime.to_unix(&1.at, :microsecond))
  end

  @doc """
  Writes the lines as `.log` text or `.jsonl`, one line each.
  """
  @spec render([line()], String.t()) :: iodata()
  def render(lines, "jsonl") do
    Enum.map(lines, fn line ->
      [
        Jason.encode_to_iodata!(
          Jason.OrderedObject.new(
            at: DateTime.to_iso8601(line.at),
            source: line.source,
            stream: line.stream,
            message: line.text
          )
        ),
        "\n"
      ]
    end)
  end

  def render(lines, _log) do
    Enum.map(
      lines,
      &[DateTime.to_iso8601(&1.at), " ", &1.source, " ", &1.stream, " ", &1.text, "\n"]
    )
  end

  @doc """
  The file name of an export, like `deployex-logs-myhost-20261029-141819.log`.
  """
  @spec filename(String.t(), String.t()) :: String.t()
  def filename(host, format) do
    host = String.replace(host, ~r/[^A-Za-z0-9._-]/, "-")
    time = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    "deployex-logs-#{host}-#{time}.#{if format == "jsonl", do: "jsonl", else: "log"}"
  end

  defp list(value) when is_binary(value), do: String.split(value, ",", trim: true)
  defp list(_value), do: []

  # The events, and the sources the log server keeps or an instance runs
  defp known_sources(asked) do
    known =
      MapSet.new(
        ["events", "deployex"] ++
          Enum.map(Logs.list_active_snames(), &to_string/1) ++
          Enum.map(Deployer.Monitor.list(), &to_string/1)
      )

    Enum.filter(asked, &MapSet.member?(known, &1))
  end

  defp minutes(%{"since" => since}) when is_binary(since) do
    case Integer.parse(since) do
      {since, ""} -> clamp(div(System.os_time(:second) - since, 60) + 1)
      _ -> 60
    end
  end

  defp minutes(%{"minutes" => minutes}) when is_binary(minutes) do
    case Integer.parse(minutes) do
      {minutes, ""} -> clamp(minutes)
      _ -> 60
    end
  end

  defp minutes(_params), do: 60

  defp clamp(minutes), do: minutes |> max(1) |> min(@max_minutes)

  defp log_lines(snames, types, minutes) do
    for sname <- snames,
        type <- Enum.map(Logs.get_types_by_sname(sname), &to_string/1),
        type in types,
        %{timestamp: timestamp, log: log} <-
          Logs.list_data_by_sname_log_type(sname, type, from: minutes, order: :asc),
        text <- String.split(log || "", ["\n", "\r"], trim: true) do
      %{at: DateTime.from_unix!(timestamp, :millisecond), source: sname, stream: type, text: text}
    end
  end

  defp event_lines(sources, minutes) do
    if "events" in sources do
      since = DateTime.add(DateTime.utc_now(), -minutes * 60)

      for %Recent{at: at} = recent <- Recent.list(), DateTime.compare(at, since) != :lt do
        {_tone, text} = RecentEvents.line(recent)
        %{at: at, source: "events", stream: "event", text: text}
      end
    else
      []
    end
  end

  defp holds?(_line, ""), do: true

  defp holds?(line, needle),
    do:
      String.contains?(String.downcase(line.text), needle) or
        String.contains?(String.downcase(line.source), needle)
end
