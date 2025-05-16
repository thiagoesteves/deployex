defmodule DeployexWeb.Helper do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  alias Foundation.Common
  alias Sentinel.Logs.Message

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

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
  @spec log_message_color(String.t(), String.t()) :: String.t()
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
  def normalize_id(node) when is_atom(node) do
    node |> Atom.to_string() |> normalize_id()
  end

  def normalize_id(text) do
    String.replace(text, ["@", "_"], "-")
  end

  @doc """
  Normalizes a single Message struct into one or more standardized log entries.

  This function takes a Message struct and breaks it down into individual log entries,
  splitting on newlines and applying the appropriate formatting and metadata to each line.
  """
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
end
