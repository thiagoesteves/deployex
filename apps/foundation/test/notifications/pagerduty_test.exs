defmodule Foundation.Notifications.PagerDutyTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Notifications.PagerDuty
  alias Foundation.Notifications.Worker

  @config %Worker{
    adapter: PagerDuty,
    url: nil,
    enabled: true,
    events: [:crash_restart],
    options: %{routing_key: "abc123def456"}
  }

  describe "notify/3" do
    @tag :capture_log
    test "returns :ok on a 2xx response" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 202, headers: [], body: ~s({"status":"success"})}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 1}
        assert :ok = PagerDuty.notify(:crash_restart, payload, @config)
      end
    end

    @tag :capture_log
    test "returns {:error, {:http_error, status}} on non-2xx" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 400, headers: [], body: "Bad Request"}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 1}
        assert {:error, {:http_error, 400}} = PagerDuty.notify(:crash_restart, payload, @config)
      end
    end

    @tag :capture_log
    test "returns {:error, reason} on transport error" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch -> {:error, :timeout} end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 1}
        assert {:error, :timeout} = PagerDuty.notify(:crash_restart, payload, @config)
      end
    end

    test "posts to the default PagerDuty API URL when config url is nil" do
      test_pid = self()

      with_mocks([
        {Finch, [],
         [
           build: fn :post, url, _headers, _body ->
             send(test_pid, {:url, url})
             %{}
           end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 202, headers: [], body: ""}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 1}
        PagerDuty.notify(:crash_restart, payload, @config)

        assert_receive {:url, url}
        assert url == "https://events.pagerduty.com/v2/enqueue"
      end
    end

    test "uses a custom URL when provided in config" do
      test_pid = self()
      custom_config = %{@config | url: "https://acme.pagerduty.com/v2/enqueue"}

      with_mocks([
        {Finch, [],
         [
           build: fn :post, url, _headers, _body ->
             send(test_pid, {:url, url})
             %{}
           end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 202, headers: [], body: ""}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 1}
        PagerDuty.notify(:crash_restart, payload, custom_config)

        assert_receive {:url, url}
        assert url == "https://acme.pagerduty.com/v2/enqueue"
      end
    end

    test "posts JSON with routing_key, event_action, and structured payload" do
      test_pid = self()

      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, headers, body ->
             send(test_pid, {:request, headers, body})
             %{}
           end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 202, headers: [], body: ""}}
           end
         ]}
      ]) do
        payload = %{node: :app@host, sname: "myapp-1", crash_restart_count: 1}
        PagerDuty.notify(:crash_restart, payload, @config)

        assert_receive {:request, headers, body}

        assert {"content-type", "application/json"} in headers

        decoded = Jason.decode!(body)
        assert decoded["routing_key"] == "abc123def456"
        assert decoded["event_action"] == "trigger"
        assert is_map(decoded["payload"])
        assert is_binary(decoded["payload"]["summary"])
        assert decoded["payload"]["severity"] == "error"
        assert decoded["payload"]["source"] == "app@host"
        assert is_map(decoded["payload"]["custom_details"])
      end
    end

    test "assigns correct severity for each event" do
      severities = [
        {:crash_restart, %{node: :n@h, sname: "s", crash_restart_count: 1}, "error"},
        {:deployment_started, %{node: :n@h, sname: "s", version: "1.0"}, "info"},
        {:deployment_complete, %{node: :n@h, sname: "s", status: :ok, message: "ok"}, "info"},
        {:deployment_complete, %{node: :n@h, sname: "s", status: :error, message: "fail"},
         "error"},
        {:deployment_shutdown, %{node: :n@h, sname: "s"}, "warning"},
        {:watchdog_threshold_exceeded,
         %{node: :n@h, type: :memory, current_percentage: 96, restart_threshold_percent: 95},
         "critical"},
        {:watchdog_threshold_warning,
         %{
           node: :n@h,
           type: :atom,
           current_percentage: 78,
           warning_threshold_percent: 75,
           action: :warning
         }, "warning"},
        {:watchdog_threshold_warning,
         %{
           node: :n@h,
           type: :atom,
           current_percentage: 70,
           warning_threshold_percent: 75,
           action: :normalized
         }, "info"},
        {:certificate_renewed, %{app_name: "app", domains: ["ex.com"]}, "info"},
        {:certificate_failed, %{app_name: "app", domains: ["ex.com"], reason: "timeout"}, "error"}
      ]

      test_pid = self()

      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, body ->
             send(test_pid, {:body, body})
             %{}
           end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 202, headers: [], body: ""}}
           end
         ]}
      ]) do
        Enum.each(severities, fn {event, payload, expected_severity} ->
          PagerDuty.notify(event, payload, @config)
          assert_receive {:body, body}
          decoded = Jason.decode!(body)

          assert decoded["payload"]["severity"] == expected_severity,
                 "expected #{expected_severity} for #{event}, got #{decoded["payload"]["severity"]}"
        end)
      end
    end
  end
end
