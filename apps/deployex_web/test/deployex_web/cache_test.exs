defmodule DeployexWeb.CacheTest do
  use ExUnit.Case, async: false

  alias DeployexWeb.Cache

  test "keeps a value for a key, and returns nil for a key it does not have" do
    assert Cache.set(:cache_test_key, %{a: 1}) == :ok
    assert Cache.get(:cache_test_key) == %{a: 1}
    assert Cache.get(:cache_test_missing) == nil
  end
end
