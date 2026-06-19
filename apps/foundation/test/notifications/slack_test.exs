defmodule Foundation.Notifications.SlackTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Notifications.Slack
  alias Foundation.Notifications.Worker

  @config %Worker{
    adapter: Slack,
    url: "https://hooks.slack.com/services/T000/B000/XXX",
    enabled: true,
    events: ["crash_restart"],
    options: %{username: "DeployEx", icon_emoji: ":robot_face:"}
  }

  describe "notify/3" do
    @tag :capture_log
    test "returns :ok on a 2xx response" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 200, headers: [], body: "ok"}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 2}
        assert :ok = Slack.notify("crash_restart", payload, @config)
      end
    end

    @tag :capture_log
    test "returns {:error, {:http_error, status}} on non-2xx" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 400, headers: [], body: "no_text"}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 2}
        assert {:error, {:http_error, 400}} = Slack.notify("crash_restart", payload, @config)
      end
    end

    @tag :capture_log
    test "returns {:error, reason} on transport error" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch -> {:error, :econnrefused} end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 2}
        assert {:error, :econnrefused} = Slack.notify("crash_restart", payload, @config)
      end
    end

    test "posts JSON with text, username and icon_emoji fields" do
      test_pid = self()

      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, headers, body ->
             send(test_pid, {:request, headers, body})
             %{}
           end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 200, headers: [], body: "ok"}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 2}
        Slack.notify("crash_restart", payload, @config)

        assert_receive {:request, headers, body}

        assert {"content-type", "application/json"} in headers

        decoded = Jason.decode!(body)
        assert is_binary(decoded["text"])
        assert decoded["username"] == "DeployEx"
        assert decoded["icon_emoji"] == ":robot_face:"
      end
    end

    test "uses default username and icon when options are absent" do
      test_pid = self()
      config_no_opts = %{@config | options: %{}}

      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, body ->
             send(test_pid, {:body, body})
             %{}
           end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 200, headers: [], body: "ok"}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 1}
        Slack.notify("crash_restart", payload, config_no_opts)

        assert_receive {:body, body}

        decoded = Jason.decode!(body)
        assert decoded["username"] == "DeployEx"
        assert decoded["icon_emoji"] == ":robot_face:"
      end
    end

    test "formats all supported events without raising" do
      events_and_payloads = [
        {"crash_restart", %{node: :n@h, sname: "s-1", crash_restart_count: 1}},
        {"deployment_started", %{node: :n@h, sname: "s-1", version: "1.0.0"}},
        {"deployment_complete", %{node: :n@h, sname: "s-1", status: :ok, message: "done"}},
        {"deployment_complete", %{node: :n@h, sname: "s-1", status: :error, message: "fail"}},
        {"deployment_shutdown", %{node: :n@h, sname: "s-1"}},
        {"watchdog_threshold_exceeded",
         %{node: :n@h, type: :memory, current_percentage: 96, restart_threshold_percent: 95}},
        {"watchdog_threshold_warning",
         %{
           node: :n@h,
           type: :atom,
           current_percentage: 78,
           warning_threshold_percent: 75,
           action: :warning
         }},
        {"watchdog_threshold_warning",
         %{
           node: :n@h,
           type: :atom,
           current_percentage: 70,
           warning_threshold_percent: 75,
           action: :normalized
         }},
        {"certificate_renewed", %{app_name: "myapp", domains: ["example.com"]}},
        {"certificate_failed", %{app_name: "myapp", domains: ["example.com"], reason: "timeout"}}
      ]

      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 200, headers: [], body: "ok"}}
           end
         ]}
      ]) do
        Enum.each(events_and_payloads, fn {event, payload} ->
          assert :ok = Slack.notify(event, payload, @config)
        end)
      end
    end
  end
end
