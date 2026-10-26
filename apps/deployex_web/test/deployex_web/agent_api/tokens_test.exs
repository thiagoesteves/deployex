defmodule DeployexWeb.AgentApi.TokensTest do
  use DeployexWeb.AgentApiCase

  import ExUnit.CaptureLog

  alias DeployexWeb.AgentApi.Tokens

  @hash String.duplicate("ab", 32)

  describe "parse/1" do
    test "returns no entry without the secret" do
      assert Tokens.parse(nil) == {[], []}
    end

    test "parses each entry, with the hash decoded" do
      assert {[ci, controller], []} =
               Tokens.parse("ci:read:#{@hash}, controller:read+read:#{String.upcase(@hash)}")

      assert ci == %{name: "ci", scopes: ["read"], hash: Base.decode16!(@hash, case: :lower)}
      assert controller.name == "controller"
      assert controller.scopes == ["read"]
    end

    test "returns the position of each invalid entry and keeps the valid ones" do
      value =
        Enum.join(
          [
            "ci:read:#{@hash}",
            "no-scope::#{@hash}",
            "unknown:operate:#{@hash}",
            "short:read:abcd",
            "not-hex:read:#{String.duplicate("zz", 32)}",
            "bad name:read:#{@hash}",
            "two:parts"
          ],
          ","
        )

      assert {[%{name: "ci"}], [2, 3, 4, 5, 6, 7]} = Tokens.parse(value)
    end

    test "counts a value that is not a string as one invalid entry" do
      assert Tokens.parse([%{"name" => "ci"}]) == {[], [1]}
    end
  end

  describe "authenticate/1" do
    test "returns the entry that matches the token" do
      put_api_tokens(
        token_entry("ci", "read", "secret-1") <> "," <> token_entry("cd", "read", "secret-2")
      )

      assert {:ok, %{name: "cd", scopes: ["read"]}} = Tokens.authenticate("secret-2")
    end

    test "refuses an unknown, empty or missing token" do
      put_api_tokens(token_entry("ci", "read", "secret-1"))

      assert Tokens.authenticate("secret-2") == :error
      assert Tokens.authenticate("") == :error
      assert Tokens.authenticate(nil) == :error
    end

    test "refuses every token when no token is configured" do
      assert Tokens.authenticate("secret-1") == :error
    end
  end

  test "allows?/2 checks the scope of an entry" do
    assert Tokens.allows?(%{scopes: ["read"]}, "read")
    refute Tokens.allows?(%{scopes: ["read"]}, "operate")
  end

  describe "warn_if_misconfigured/0" do
    test "logs each invalid entry by position, without its value" do
      put_api_tokens("ci:read:#{@hash},broken")

      log = capture_log(fn -> assert Tokens.warn_if_misconfigured() == :ok end)

      assert log =~ "Agent API token entry 2 in DEPLOYEX_API_TOKENS is ignored"
      refute log =~ "broken"
    end

    test "logs when the API is on with no valid token" do
      config = Application.get_env(:deployex_web, DeployexWeb.AgentApi.Endpoint)

      Application.put_env(
        :deployex_web,
        DeployexWeb.AgentApi.Endpoint,
        Keyword.put(config, :server, true)
      )

      on_exit(fn -> Application.put_env(:deployex_web, DeployexWeb.AgentApi.Endpoint, config) end)

      assert capture_log(fn -> Tokens.warn_if_misconfigured() end) =~
               "Agent API is on with no valid token"
    end

    test "logs nothing when the API is off" do
      assert capture_log(fn -> Tokens.warn_if_misconfigured() end) == ""
    end
  end
end
