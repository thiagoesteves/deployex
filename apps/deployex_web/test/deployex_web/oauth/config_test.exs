defmodule DeployexWeb.OAuth.ConfigTest do
  # async: false, the tests change the shared application environment
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias DeployexWeb.OAuth.Config

  @complete [
    client_id: "Ov23liExample",
    client_secret: "secret",
    redirect_uri: "http://localhost:5001/auth/github/callback"
  ]

  setup do
    original = Application.get_env(:deployex_web, DeployexWeb.OAuth)

    on_exit(fn ->
      if original do
        Application.put_env(:deployex_web, DeployexWeb.OAuth, original)
      else
        Application.delete_env(:deployex_web, DeployexWeb.OAuth)
      end
    end)

    :ok
  end

  test "configured? is false without a client_id" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth, [])
    refute Config.configured?()
  end

  test "configured? is true when the client_id, client_secret and redirect_uri are set" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth, @complete)
    assert Config.configured?()
  end

  test "configured? is false when any of them is missing or empty" do
    for key <- Keyword.keys(@complete), value <- [nil, ""] do
      Application.put_env(:deployex_web, DeployexWeb.OAuth, Keyword.put(@complete, key, value))
      refute Config.configured?(), "expected not configured with #{key} = #{inspect(value)}"
    end
  end

  test "warn_if_incomplete names what is missing when only part is set" do
    incomplete = Keyword.delete(@complete, :client_secret)
    Application.put_env(:deployex_web, DeployexWeb.OAuth, incomplete)

    assert capture_log(fn -> assert :ok = Config.warn_if_incomplete() end) =~
             "OAuth sign-in is off because the config has no DEPLOYEX_OAUTH_CLIENT_SECRET"
  end

  test "warn_if_incomplete warns for an allowlist without the required values" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth,
      allowlist: %{emails: ["me@co.com"], domains: []}
    )

    assert capture_log(fn -> assert :ok = Config.warn_if_incomplete() end) =~
             "the config has no auth.client_id, DEPLOYEX_OAUTH_CLIENT_SECRET, auth.redirect_uri"
  end

  test "warn_if_incomplete is silent when OAuth is fully set or not set at all" do
    for config <- [@complete, [], [allowlist: %{emails: [], domains: []}]] do
      Application.put_env(:deployex_web, DeployexWeb.OAuth, config)
      assert capture_log(fn -> assert :ok = Config.warn_if_incomplete() end) == ""
    end
  end

  test "provider_module defaults to GitHub" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth, [])
    assert Config.provider_module() == DeployexWeb.OAuth.Provider.GitHub
  end

  test "provider_module can be overridden" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth,
      provider: DeployexWeb.OAuth.ProviderMock
    )

    assert Config.provider_module() == DeployexWeb.OAuth.ProviderMock
  end

  test "allowlist defaults to deny-all (empty)" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth, [])
    assert Config.allowlist() == %{emails: [], domains: []}
  end

  test "allowlist is returned from config" do
    allowlist = %{emails: ["me@co.com"], domains: ["co.com"]}
    Application.put_env(:deployex_web, DeployexWeb.OAuth, allowlist: allowlist)
    assert Config.allowlist() == allowlist
  end
end
