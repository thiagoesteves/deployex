defmodule Deployex.Log do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Return the expected background color for the respective message type

  PS: It wasn't possible to use bg-color-[value] since the table wasn't working
      as expected

  ## Examples

    iex> alias Deployex.Log
    ...> assert Log.log_message_color("any", "stderr") == "#F87171"
    ...> assert Log.log_message_color("debug", "stdout") == "#E5E5E5"
    ...> assert Log.log_message_color("DEBUG", "stdout") == "#E5E5E5"
    ...> assert Log.log_message_color("info", "stdout") == "#93C5FD"
    ...> assert Log.log_message_color("INFO", "stdout") == "#93C5FD"
    ...> assert Log.log_message_color("warning", "stdout") == "#FBBF24"
    ...> assert Log.log_message_color("WARNING", "stdout") == "#FBBF24"
    ...> assert Log.log_message_color("error", "stdout") == "#F87171"
    ...> assert Log.log_message_color("ERROR", "stdout") == "#F87171"
    ...> assert Log.log_message_color("SIGTERM", "stdout") == "#F87171"
    ...> assert Log.log_message_color("notice", "stdout") == "#FDBA74"
    ...> assert Log.log_message_color("NOTICE", "stdout") == "#FDBA74"
    ...> assert Log.log_message_color("any", "stdout") == "#E5E5E5"
  """
  @spec log_message_color(String.t(), String.t()) :: String.t()
  def log_message_color(_message, "stderr"), do: "#F87171"

  def log_message_color(message, _log_type) do
    cond do
      String.contains?(message, ["debug", "DEBUG"]) ->
        "#E5E5E5"

      String.contains?(message, ["info", "INFO"]) ->
        "#93C5FD"

      String.contains?(message, ["warning", "WARNING"]) ->
        "#FBBF24"

      String.contains?(message, ["error", "ERROR", "SIGTERM"]) ->
        "#F87171"

      String.contains?(message, ["notice", "NOTICE"]) ->
        "#FDBA74"

      true ->
        "#E5E5E5"
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
