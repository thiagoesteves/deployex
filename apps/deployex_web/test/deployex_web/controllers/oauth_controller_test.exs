defmodule DeployexWeb.OAuthControllerTest do
  # async: false, it changes the shared application environment. It calls the
  # actions directly with the ProviderMock so no real OAuth round-trip runs.
  use DeployexWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias DeployexWeb.OAuth.ProviderMock

  setup :verify_on_exit!

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

  defp put_oauth_config(allowlist) do
    Application.put_env(:deployex_web, DeployexWeb.OAuth,
      provider: ProviderMock,
      allowlist: allowlist
    )
  end

  defp base_conn(session \\ %{}) do
    build_conn()
    |> Plug.Test.init_test_session(session)
    |> Phoenix.Controller.fetch_flash([])
  end

  # A callback always follows a request that stored the session params
  defp callback_conn, do: base_conn(%{oauth_session_params: %{state: "s"}})

  test "request redirects to the provider and stores session params" do
    put_oauth_config(%{emails: [], domains: []})

    expect(ProviderMock, :authorize_url, fn ->
      {:ok, %{url: "https://github.com/login/oauth/authorize?x=1", session_params: %{state: "s"}}}
    end)

    conn = base_conn() |> DeployexWeb.OAuthController.request(%{"provider" => "github"})

    assert redirected_to(conn) == "https://github.com/login/oauth/authorize?x=1"
    assert get_session(conn, :oauth_session_params) == %{state: "s"}
  end

  test "callback with an allowed verified email logs in" do
    put_oauth_config(%{emails: ["me@co.com"], domains: []})

    expect(ProviderMock, :callback, fn _params, _sp ->
      {:ok, %{email: "me@co.com", verified?: true}}
    end)

    conn =
      callback_conn()
      |> DeployexWeb.OAuthController.callback(%{"provider" => "github", "code" => "abc"})

    assert get_session(conn, :oauth_email) == "me@co.com"
    assert redirected_to(conn) == "/applications"
  end

  test "callback with a non-allow-listed email is denied" do
    put_oauth_config(%{emails: [], domains: []})

    expect(ProviderMock, :callback, fn _p, _sp ->
      {:ok, %{email: "x@evil.com", verified?: true}}
    end)

    log =
      capture_log(fn ->
        conn =
          callback_conn()
          |> DeployexWeb.OAuthController.callback(%{"provider" => "github", "code" => "abc"})

        assert get_session(conn, :oauth_email) == nil
        assert redirected_to(conn) == "/users/log_in"
      end)

    assert log =~ ~s(OAuth sign-in denied: {:not_in_allowlist, "x@evil.com"})
  end

  test "callback error is denied" do
    put_oauth_config(%{emails: [], domains: []})
    expect(ProviderMock, :callback, fn _p, _sp -> {:error, :bad} end)

    log =
      capture_log(fn ->
        conn =
          callback_conn()
          |> DeployexWeb.OAuthController.callback(%{"provider" => "github", "code" => "abc"})

        assert get_session(conn, :oauth_email) == nil
        assert redirected_to(conn) == "/users/log_in"
      end)

    assert log =~ "OAuth sign-in denied: :bad"
  end

  test "callback with an unverified email is denied" do
    put_oauth_config(%{emails: ["me@co.com"], domains: []})

    expect(ProviderMock, :callback, fn _p, _sp ->
      {:ok, %{email: "me@co.com", verified?: false}}
    end)

    log =
      capture_log(fn ->
        conn =
          callback_conn()
          |> DeployexWeb.OAuthController.callback(%{"provider" => "github", "code" => "abc"})

        assert get_session(conn, :oauth_email) == nil
        assert redirected_to(conn) == "/users/log_in"
      end)

    assert log =~ ~s(OAuth sign-in denied: {:unverified_email, "me@co.com"})
  end

  test "callback without a sign-in in progress is denied without calling the provider" do
    put_oauth_config(%{emails: ["me@co.com"], domains: []})

    log =
      capture_log(fn ->
        conn =
          base_conn()
          |> DeployexWeb.OAuthController.callback(%{"provider" => "github", "code" => "abc"})

        assert get_session(conn, :oauth_email) == nil
        assert redirected_to(conn) == "/users/log_in"
      end)

    assert log =~ "OAuth sign-in denied: :no_sign_in_in_progress"
  end
end
