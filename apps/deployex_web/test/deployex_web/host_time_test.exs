defmodule DeployexWeb.HostTimeTest do
  use ExUnit.Case, async: true

  alias DeployexWeb.HostTime

  test "local keeps the time, in the host's time zone" do
    utc = ~U[2026-10-30 03:06:12.694Z]
    local = HostTime.local(utc)

    {date, time} = :calendar.universal_time_to_local_time({{2026, 10, 30}, {3, 6, 12}})
    assert local == NaiveDateTime.from_erl!({date, time}, {694_000, 3})
    assert HostTime.format(utc, "%H:%M:%S.%f") == Calendar.strftime(local, "%H:%M:%S.%f")
  end

  test "zone names the offset that local applies now" do
    zone = HostTime.zone()
    assert zone =~ ~r/^UTC([+-]\d{1,2}(:\d{2})?)?$/

    now = DateTime.utc_now()
    offset = div(NaiveDateTime.diff(HostTime.local(now), DateTime.to_naive(now)), 60)

    expected =
      case Regex.run(~r/^UTC([+-])(\d+)(?::(\d{2}))?$/, zone) do
        nil ->
          0

        [_all, sign, hours] ->
          String.to_integer(sign <> hours) * 60

        [_all, sign, hours, rest] ->
          String.to_integer(sign <> "1") *
            (String.to_integer(hours) * 60 + String.to_integer(rest))
      end

    assert offset == expected
  end
end
