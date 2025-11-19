defmodule Host.Info.Uptime do
  @moduledoc """
  Reads host uptime across Linux, macOS, and Windows platforms.
  """

  alias Host.Commander

  @type t :: %__MODULE__{
          uptime: nil | String.t()
        }

  defstruct uptime: nil

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec get_linux() :: t()
  def get_linux do
    case Commander.run("cat /proc/uptime", [:stdout, :sync]) do
      {:ok, [{:stdout, stdout}]} ->
        uptime =
          stdout
          |> List.first()
          |> String.split()
          |> List.first()
          |> String.to_float()
          |> format_uptime()

        %__MODULE__{uptime: uptime}

      _ ->
        %__MODULE__{}
    end
  end

  @spec get_macos() :: t()
  def get_macos do
    with {:ok, [{:stdout, stdout_kern_boottime}]} <-
           Commander.run("sysctl -n kern.boottime", [:stdout, :sync]),
         stdout <- Enum.join(stdout_kern_boottime, ""),
         [_, boot_time_str] <- Regex.run(~r/sec = (\d+)/, stdout) do
      boot_time = String.to_integer(boot_time_str)
      current_time = System.os_time(:second)
      uptime_seconds = current_time - boot_time
      format_uptime(uptime_seconds)

      %__MODULE__{uptime: format_uptime(uptime_seconds)}
    else
      _ ->
        %__MODULE__{}
    end
  end

  @spec get_windows() :: t()
  def get_windows, do: %__MODULE__{}

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp format_uptime(seconds) when is_float(seconds) do
    format_uptime(trunc(seconds))
  end

  defp format_uptime(seconds) when is_integer(seconds) do
    cond do
      seconds >= 86_400 ->
        days = div(seconds, 86_400)
        "#{days} #{pluralize("day", days)}"

      seconds >= 3600 ->
        hours = div(seconds, 3600)
        "#{hours} #{pluralize("hour", hours)}"

      seconds >= 60 ->
        minutes = div(seconds, 60)
        "#{minutes} #{pluralize("minute", minutes)}"

      true ->
        "#{seconds} #{pluralize("second", seconds)}"
    end
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"
end
