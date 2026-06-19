defmodule Foundation.Notifications.WebhookTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Notifications.Webhook
  alias Foundation.Notifications.Worker

  @config %Worker{
    adapter: Webhook,
    url: "https://hooks.example.com/deployex",
    enabled: true,
    events: ["crash_restart"],
    options: %{}
  }

  @payload %{node: :deployex@host, sname: "myapp-1", crash_restart_count: 1}

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
        assert :ok = Webhook.notify("crash_restart", @payload, @config)
      end
    end

    @tag :capture_log
    test "returns :ok for any 2xx status code" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 204, headers: [], body: ""}}
           end
         ]}
      ]) do
        assert :ok = Webhook.notify("crash_restart", @payload, @config)
      end
    end

    @tag :capture_log
    test "returns {:error, {:http_error, status}} on a non-2xx response" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 500, headers: [], body: "Internal Server Error"}}
           end
         ]}
      ]) do
        assert {:error, {:http_error, 500}} =
                 Webhook.notify("crash_restart", @payload, @config)
      end
    end

    @tag :capture_log
    test "returns {:error, reason} on a transport error" do
      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, _headers, _body -> %{} end,
           request: fn _req, Foundation.Finch -> {:error, :timeout} end
         ]}
      ]) do
        assert {:error, :timeout} = Webhook.notify("crash_restart", @payload, @config)
      end
    end

    test "posts JSON with event, timestamp and payload fields" do
      test_pid = self()

      with_mocks([
        {Finch, [],
         [
           build: fn :post, _url, headers, body ->
             send(test_pid, {:request_body, headers, body})
             %{}
           end,
           request: fn _req, Foundation.Finch ->
             {:ok, %Finch.Response{status: 200, headers: [], body: "ok"}}
           end
         ]}
      ]) do
        Webhook.notify("crash_restart", @payload, @config)

        assert_receive {:request_body, headers, body}

        assert {"content-type", "application/json"} in headers

        decoded = Jason.decode!(body)
        assert decoded["event"] == "crash_restart"
        assert is_binary(decoded["timestamp"])
        assert is_map(decoded["payload"])
      end
    end
  end
end
