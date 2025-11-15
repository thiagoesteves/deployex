defmodule Sentinel.LogsTest do
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  alias Foundation.Catalog
  alias Sentinel.Logs

  test "subscribe_for_new_logs/2" do
    sname = Catalog.create_sname("sentinel_app")

    Sentinel.LogsMock
    |> expect(:subscribe_for_new_logs, fn _sname, _type -> :ok end)

    assert :ok = Logs.subscribe_for_new_logs(sname, :type)
  end

  test "unsubscribe_for_new_logs/2" do
    sname = Catalog.create_sname("sentinel_app")

    Sentinel.LogsMock
    |> expect(:unsubscribe_for_new_logs, fn _sname, _type -> :ok end)

    assert :ok = Logs.unsubscribe_for_new_logs(sname, :type)
  end

  test "list_data_by_sname_log_type/2" do
    sname = Catalog.create_sname("sentinel_app")

    Sentinel.LogsMock
    |> expect(:list_data_by_sname_log_type, fn _sname, _type, _options -> [] end)

    assert [] = Logs.list_data_by_sname_log_type(sname, :type, [])
  end

  test "get_types_by_sname/1" do
    sname = Catalog.create_sname("sentinel_app")

    Sentinel.LogsMock
    |> expect(:get_types_by_sname, fn _sname -> [] end)

    assert [] = Logs.get_types_by_sname(sname)
  end

  test "list_active_snames/0" do
    Sentinel.LogsMock
    |> expect(:list_active_snames, fn -> [] end)

    assert [] = Logs.list_active_snames()
  end

  test "update_data_retention_period/1" do
    Sentinel.LogsMock
    |> expect(:update_data_retention_period, fn _value -> :ok end)

    assert :ok = Logs.update_data_retention_period(30_000)
  end
end
