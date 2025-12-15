defmodule DeployexWeb.Helper do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  alias Foundation.Catalog
  alias Foundation.Common
  alias Sentinel.Logs.Message

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Return the expected color for status badge

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.status_color(:running) == "bg-success border-b border-success/20"
    ...> assert Helper.status_color(:starting) == "bg-warning border-b border-warning/20"
    ...> assert Helper.status_color(:pre_commands) == "bg-info border-b border-info/20"
    ...> assert Helper.status_color(:any) == "bg-neutral border-b border-neutral/20"
  """
  @spec status_color(status :: atom()) :: String.t()
  def status_color(:running), do: "bg-success border-b border-success/20"
  def status_color(:starting), do: "bg-warning border-b border-warning/20"
  def status_color(:pre_commands), do: "bg-info border-b border-info/20"
  def status_color(_), do: "bg-neutral border-b border-neutral/20"

  @doc """
  Return the expected background color for the respective message type

  PS: It wasn't possible to use bg-color-[value] since the table wasn't working
      as expected

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.log_message_color("any", "stderr") == "#F87171"
    ...> assert Helper.log_message_color("[debug]", "stdout") == "#E5E5E5"
    ...> assert Helper.log_message_color("DEBUG", "stdout") == "#E5E5E5"
    ...> assert Helper.log_message_color("[info]", "stdout") == "#93C5FD"
    ...> assert Helper.log_message_color("INFO", "stdout") == "#93C5FD"
    ...> assert Helper.log_message_color("[warning]", "stdout") == "#FBBF24"
    ...> assert Helper.log_message_color("WARNING", "stdout") == "#FBBF24"
    ...> assert Helper.log_message_color("[error]", "stdout") == "#F87171"
    ...> assert Helper.log_message_color("ERROR", "stdout") == "#F87171"
    ...> assert Helper.log_message_color("SIGTERM", "stdout") == "#F87171"
    ...> assert Helper.log_message_color("[notice]", "stdout") == "#FDBA74"
    ...> assert Helper.log_message_color("NOTICE", "stdout") == "#FDBA74"
    ...> assert Helper.log_message_color("any", "stdout") == "#E5E5E5"
  """
  @spec log_message_color(message :: String.t(), log_type :: String.t()) :: String.t()
  def log_message_color(_message, "stderr"), do: "#F87171"

  def log_message_color(message, _log_type) do
    cond do
      String.contains?(message, ["[error]", "error", "ERROR", "SIGTERM"]) ->
        "#F87171"

      String.contains?(message, ["[info]", "INFO"]) ->
        "#93C5FD"

      String.contains?(message, ["[warning]", "WARNING"]) ->
        "#FBBF24"

      String.contains?(message, ["[notice]", "notice", "NOTICE"]) ->
        "#FDBA74"

      String.contains?(message, ["[debug]", "DEBUG"]) ->
        "#E5E5E5"

      true ->
        "#E5E5E5"
    end
  end

  @doc """
  Normalizes a list of log messages into a standardized format.

  This function processes a collection of log messages, converting each message 
  into a normalized format containing expected attributes such as color, service 
  identifiers, and categorization.
  """
  @spec normalize_logs(
          messages :: list(Message.t()),
          service :: String.t(),
          log_type :: String.t()
        ) :: list(map())
  def normalize_logs(messages, service, log_type) do
    Enum.reduce(messages, [], fn message, acc ->
      acc ++ normalize_log(message, service, log_type)
    end)
  end

  @doc """
  This function exchange "_" and "@" to -

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.normalize_id(:"my_app-1@host") == "my-app-1-host"
    ...> assert Helper.normalize_id("my_app-2@host") == "my-app-2-host"
  """
  @spec normalize_id(node :: atom() | String.t()) :: String.t()
  def normalize_id(node) when is_atom(node) do
    node |> Atom.to_string() |> normalize_id()
  end

  def normalize_id(text) do
    String.replace(text, ["@", "_"], "-")
  end

  @doc """
  This function return the node from a node_info request
  """
  @spec sname_to_node(sname :: String.t()) :: atom()
  def sname_to_node(sname) do
    %{node: node} = Catalog.node_info(sname)
    node
  end

  @doc """
  This function return the short name for the self node
  """
  @spec self_sname() :: String.t()
  def self_sname do
    [sname, _hostname] = Node.self() |> Atom.to_string() |> String.split(["@"])
    sname
  end

  @doc """
  Normalizes a single Message struct into one or more standardized log entries.

  This function takes a Message struct and breaks it down into individual log entries,
  splitting on newlines and applying the appropriate formatting and metadata to each line.
  """
  @spec normalize_log(message :: Message.t(), service :: String.t(), log_type :: String.t()) ::
          list(map())
  def normalize_log(%Message{log: log, timestamp: timestamp}, service, log_type) do
    log
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.map(fn content ->
      color = log_message_color(content, log_type)

      %{
        id: Common.uuid4(),
        timestamp: timestamp,
        content: content,
        color: color,
        service: service,
        type: log_type
      }
    end)
  end

  @doc """
  Converts milliseconds into a human-readable string.

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.format_ms_to_readable(3_600_000) == "1.0h"
    ...> assert Helper.format_ms_to_readable(60_000) == "1.0m"
    ...> assert Helper.format_ms_to_readable(1000) == "1.0s"
    ...> assert Helper.format_ms_to_readable(100) == "100ms"
    ...> assert Helper.format_ms_to_readable(nil) == "N/A"
  """
  @spec format_ms_to_readable(ms :: integer()) :: String.t()
  def format_ms_to_readable(ms) when is_integer(ms) do
    cond do
      ms >= 3_600_000 -> "#{Float.round(ms / 3_600_000, 1)}h"
      ms >= 60_000 -> "#{Float.round(ms / 60_000, 1)}m"
      ms >= 1000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{ms}ms"
    end
  end

  def format_ms_to_readable(_), do: "N/A"

  @doc """
  Format bytes to human readable string

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.format_bytes(1000) == "1000 B"
    ...> assert Helper.format_bytes(1_048_575) == "1024.0 KB"
    ...> assert Helper.format_bytes(1_073_741_823) == "1024.0 MB"
    ...> assert Helper.format_bytes(1_073_741_824) == "1.0 GB"
  """
  @spec format_bytes(bytes :: non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"

  def format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"

  def format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  @doc """
  Format error to human readable string

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.error_to_string(:too_large) == "File is too large"
    ...> assert Helper.error_to_string(:not_accepted) == "File type not accepted"
    ...> assert Helper.error_to_string(:too_many_files) == "Too many files"
    ...> assert Helper.error_to_string({:error, :invalid}) == "Upload error: {:error, :invalid}"
  """
  def error_to_string(:too_large), do: "File is too large"
  def error_to_string(:not_accepted), do: "File type not accepted"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(error), do: "Upload error: #{inspect(error)}"
end
