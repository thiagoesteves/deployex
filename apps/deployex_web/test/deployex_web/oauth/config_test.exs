defmodule DeployexWeb.OAuth.ConfigTest do
  # async: false — these tests mutate the shared application environment.
  use ExUnit.Case, async: false

  alias DeployexWeb.OAuth.Config

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

  test "configured? is true when a client_id is present" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth, client_id: "Iv1.abc123")
    assert Config.configured?()
  end

  test "provider_module defaults to GitHub" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth, [])
    assert Config.provider_module() == DeployexWeb.OAuth.Provider.GitHub
  end

  test "provider_module can be overridden" do
    Application.put_env(:deployex_web, DeployexWeb.OAuth, provider: DeployexWeb.OAuth.ProviderMock)
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
