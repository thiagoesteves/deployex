defmodule Deployex.Log do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Return the expected background color for the respective message type

  ## Examples

    iex> alias Deployex.Log
    ...> assert Log.log_message_color("any", "stderr") == "bg-red-500"
    ...> assert Log.log_message_color("debug", "stdout") == "bg-gray-300"
    ...> assert Log.log_message_color("DEBUG", "stdout") == "bg-gray-300"
    ...> assert Log.log_message_color("info", "stdout") == "bg-blue-300"
    ...> assert Log.log_message_color("INFO", "stdout") == "bg-blue-300"
    ...> assert Log.log_message_color("warning", "stdout") == "bg-yellow-400"
    ...> assert Log.log_message_color("WARNING", "stdout") == "bg-yellow-400"
    ...> assert Log.log_message_color("error", "stdout") == "bg-red-500"
    ...> assert Log.log_message_color("ERROR", "stdout") == "bg-red-500"
    ...> assert Log.log_message_color("SIGTERM", "stdout") == "bg-red-500"
    ...> assert Log.log_message_color("notice", "stdout") == "bg-orange-300"
    ...> assert Log.log_message_color("NOTICE", "stdout") == "bg-orange-300"
    ...> assert Log.log_message_color("any", "stdout") == "bg-gray-300"
  """
  @spec log_message_color(String.t(), String.t()) :: String.t()
  def log_message_color(_message, "stderr"), do: "bg-red-500"

  def log_message_color(message, _log_type) do
    cond do
      String.contains?(message, ["debug", "DEBUG"]) ->
        "bg-gray-300"

      String.contains?(message, ["info", "INFO"]) ->
        "bg-blue-300"

      String.contains?(message, ["warning", "WARNING"]) ->
        "bg-yellow-400"

      String.contains?(message, ["error", "ERROR", "SIGTERM"]) ->
        "bg-red-500"

      String.contains?(message, ["notice", "NOTICE"]) ->
        "bg-orange-300"

      true ->
        "bg-gray-300"
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
