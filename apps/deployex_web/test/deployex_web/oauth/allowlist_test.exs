defmodule DeployexWeb.OAuth.AllowlistTest do
  use ExUnit.Case, async: true

  alias DeployexWeb.OAuth.Allowlist

  test "empty or nil allowlist denies everyone (fail closed)" do
    assert Allowlist.check("me@co.com", %{emails: [], domains: []}) == :denied
    assert Allowlist.check("me@co.com", %{}) == :denied
    assert Allowlist.check("me@co.com", nil) == :denied
  end

  test "exact email match is allowed" do
    assert Allowlist.check("me@co.com", %{emails: ["me@co.com"], domains: []}) == :ok
  end

  test "domain match is allowed" do
    assert Allowlist.check("anyone@co.com", %{emails: [], domains: ["co.com"]}) == :ok
  end

  test "no match is denied" do
    assert Allowlist.check("stranger@evil.com", %{emails: ["me@co.com"], domains: ["co.com"]}) ==
             :denied
  end

  test "matching is case-insensitive" do
    assert Allowlist.check("me@co.COM", %{emails: ["Me@Co.com"], domains: []}) == :ok
  end
end
