defmodule DeployexWeb.HostTime do
  @moduledoc """
  Times as the host's clock shows them. The apps on a host write their log stamps in its time zone, so the
  dashboard shows its times in that zone too, and names the zone by its offset from UTC.
  """

  @doc """
  Returns the host's local time of a UTC time.
  """
  @spec local(DateTime.t()) :: NaiveDateTime.t()
  def local(%DateTime{} = utc) do
    utc
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
    |> NaiveDateTime.from_erl!(utc.microsecond)
  end

  @doc """
  Formats a UTC time in the host's time zone, with a `Calendar.strftime/2` pattern.
  """
  @spec format(DateTime.t(), String.t()) :: String.t()
  def format(utc, pattern), do: utc |> local() |> Calendar.strftime(pattern)

  @doc """
  Returns the host's offset from UTC now, like `UTC-4`, `UTC+5:30` or `UTC`.
  """
  @spec zone() :: String.t()
  def zone do
    now = DateTime.utc_now()

    case div(NaiveDateTime.diff(local(now), DateTime.to_naive(now)), 60) do
      0 ->
        "UTC"

      minutes ->
        sign = if minutes < 0, do: "-", else: "+"
        hours = div(abs(minutes), 60)
        rest = rem(abs(minutes), 60)
        "UTC#{sign}#{hours}#{if rest > 0, do: ":#{String.pad_leading("#{rest}", 2, "0")}"}"
    end
  end
end
