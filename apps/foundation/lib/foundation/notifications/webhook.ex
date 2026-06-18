defmodule Foundation.Notifications.Webhook do
  @moduledoc """
  Notification adapter that delivers events as JSON HTTP POST requests.

  This is the generic, receiver-agnostic adapter.  Point it at any endpoint
  that accepts a POST with a JSON body (e.g. custom scripts, n8n, Zapier,
  Make, AWS API Gateway, etc.).

  ## YAML configuration

      notifications:
        - adapter: "webhook"
          url: "https://example.com/hooks/deployex"
          enabled: true
          events:
            - "crash_restart"
            - "deployment_started"
            - "deployment_complete"
            - "watchdog_threshold_exceeded"
            - "certificate_renewed"
            - "certificate_failed"

  The `options:` key is accepted but currently unused; it is reserved for
  future extensions such as custom headers or HMAC signing.

  ## Request format

  `Content-Type: application/json`, body:

      {
        "event": "crash_restart",
        "timestamp": "2025-06-18T14:30:00.000000Z",
        "payload": {
          "node": "myapp@prod-1",
          "sname": "myapp-1",
          "name": "myapp",
          "language": "elixir",
          "crash_restart_count": 3
        }
      }

  A `2xx` HTTP response is treated as success.  Any other status or transport
  error is returned as `{:error, reason}` and logged at the `warning` level.

  ## Payload fields per event

  | Event                          | Fields in `payload`                                                    |
  |--------------------------------|------------------------------------------------------------------------|
  | `crash_restart`                | `node`, `sname`, `name`, `language`, `crash_restart_count`            |
  | `deployment_started`           | `node`, `sname`, `version`                                             |
  | `deployment_complete`          | `node`, `sname`, `status` (`:ok`/`:error`), `message`                 |
  | `watchdog_threshold_exceeded`  | `node`, `sname`, `type`, `current_percentage`, `restart_threshold_percent` |
  | `certificate_renewed`          | `app_name`, `domains`                                                  |
  | `certificate_failed`           | `app_name`, `domains`, `reason`                                        |
  """

  @behaviour Foundation.Notifications.Adapter

  require Logger

  alias Foundation.Yaml

  @impl true
  @spec notify(event :: atom(), payload :: map(), config :: Yaml.Notification.t()) ::
          :ok | {:error, term()}
  def notify(event, payload, %Yaml.Notification{url: url}) do
    body =
      Jason.encode!(%{
        event: event,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        payload: payload
      })

    headers = [{"content-type", "application/json"}]

    :post
    |> Finch.build(url, headers, body)
    |> Finch.request(Foundation.Finch)
    |> handle_response(event, url)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp handle_response({:ok, %Finch.Response{status: status}}, _event, _url)
       when status in 200..299 do
    :ok
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}, event, url) do
    Logger.warning(
      "Webhook notification failed for event=#{event} url=#{url} status=#{status} body=#{body}"
    )

    {:error, {:http_error, status}}
  end

  defp handle_response({:error, reason}, event, url) do
    Logger.error(
      "Webhook notification error for event=#{event} url=#{url} reason=#{inspect(reason)}"
    )

    {:error, reason}
  end
end
