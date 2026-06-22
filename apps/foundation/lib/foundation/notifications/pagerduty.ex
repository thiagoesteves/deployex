defmodule Foundation.Notifications.PagerDuty do
  @moduledoc """
  Notification adapter that creates PagerDuty incidents via the Events API v2.

  ## How it works

  Each event is translated into a PagerDuty *trigger* action and posted to the
  [PagerDuty Events API v2](https://developer.pagerduty.com/docs/ZG9jOjExMDI5NTgw-send-an-alert-event).
  The routing key determines which PagerDuty service and escalation policy receives
  the incident.

  ## Worker configuration

      notifications:
        - adapter: "pagerduty"
          enabled: true
          url: "https://events.pagerduty.com/v2/enqueue" # optional — override the API endpoint
          events:
            - "crash_restart"
            - "watchdog_threshold_exceeded"
            - "certificate_failed"
          options:
            routing_key: "abc123def456..."   # required — PagerDuty integration key

  The `url:` field is optional.  When omitted, the standard PagerDuty Events API
  endpoint (`https://events.pagerduty.com/v2/enqueue`) is used.  Override it only
  if you are running a PagerDuty on-premises installation.

  ## Finding your routing key

  1. In PagerDuty, open *Services* → your service → *Integrations*.
  2. Add an *Events API v2* integration (or use an existing one).
  3. Copy the *Integration Key* — that is your `routing_key`.

  ## Alert severity mapping

  | DeployEx event                | PagerDuty severity |
  |-------------------------------|--------------------|
  | `crash_restart`               | `error`            |
  | `deployment_started`          | `info`             |
  | `deployment_complete` (ok)    | `info`             |
  | `deployment_complete` (error) | `error`            |
  | `watchdog_threshold_exceeded` | `critical`         |
  | `watchdog_threshold_warning`  | `warning` / `info` |
  | `certificate_renewed`         | `info`             |
  | `certificate_valid`           | `info`             |
  | `certificate_failed`          | `error`            |
  | `deployment_shutdown`         | `warning`          |
  | `config_changed`              | `warning`          |
  | `config_change_applied`       | `info`             |

  ## Payload sent to PagerDuty

      {
        "routing_key": "...",
        "event_action": "trigger",
        "payload": {
          "summary": "crash_restart — myapp-1 on myapp@prod-1",
          "severity": "error",
          "source": "myapp@prod-1",
          "custom_details": { ... event payload ... }
        }
      }
  """

  @behaviour Foundation.Notifications.Adapter

  require Logger

  alias Foundation.Notifications.Worker

  @default_api_url "https://events.pagerduty.com/v2/enqueue"

  @impl true
  @spec notify(event :: String.t(), payload :: map(), config :: Worker.t()) ::
          :ok | {:error, term()}
  def notify(event, payload, %Worker{url: url, options: options}) do
    routing_key = options[:routing_key]
    api_url = url || @default_api_url

    body =
      Jason.encode!(%{
        routing_key: routing_key,
        event_action: "trigger",
        payload: %{
          summary: format_summary(event, payload),
          severity: event_severity(event, payload),
          source: event_source(payload),
          custom_details: payload
        }
      })

    headers = [{"content-type", "application/json"}]

    :post
    |> Finch.build(api_url, headers, body)
    |> Finch.request(Foundation.Finch)
    |> handle_response(event, api_url)
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
      "PagerDuty notification failed for event=#{event} url=#{url} status=#{status} body=#{body}"
    )

    {:error, {:http_error, status}}
  end

  defp handle_response({:error, reason}, event, url) do
    Logger.error(
      "PagerDuty notification error for event=#{event} url=#{url} reason=#{inspect(reason)}"
    )

    {:error, reason}
  end

  defp format_summary("crash_restart", payload),
    do: "crash_restart — #{payload.sname} on #{payload.node}"

  defp format_summary("deployment_started", payload),
    do: "deployment_started — #{payload.sname} on #{payload.node} (version #{payload.version})"

  defp format_summary("deployment_complete", payload),
    do: "deployment_complete (#{payload.status}) — #{payload.sname} on #{payload.node}"

  defp format_summary("watchdog_threshold_exceeded", payload),
    do:
      "watchdog_threshold_exceeded — #{payload.type} at #{payload.current_percentage}% on #{payload.node}"

  defp format_summary("watchdog_threshold_warning", %{action: :warning} = payload),
    do:
      "watchdog_threshold_warning — #{payload.type} at #{payload.current_percentage}% on #{payload.node} (warning: #{payload.warning_threshold_percent}%)"

  defp format_summary("watchdog_threshold_warning", %{action: :normalized} = payload),
    do:
      "watchdog_threshold_warning — #{payload.type} normalized to #{payload.current_percentage}% on #{payload.node}"

  defp format_summary("certificate_renewed", payload),
    do: "certificate_renewed — #{payload.app_name} (#{Enum.join(payload.domains, ", ")})"

  defp format_summary("certificate_valid", payload),
    do: "certificate_valid — #{payload.app_name} (#{Enum.join(payload.domains, ", ")})"

  defp format_summary("certificate_failed", payload),
    do: "certificate_failed — #{payload.app_name}: #{payload.reason}"

  defp format_summary("deployment_shutdown", payload),
    do: "deployment_shutdown — #{payload.sname} on #{payload.node} (force-terminated)"

  defp format_summary("config_changed", payload),
    do:
      "config_changed — #{payload.changes_count} change(s) detected on #{payload.node}: #{Enum.join(payload.fields, ", ")}"

  defp format_summary("config_change_applied", payload),
    do:
      "config_change_applied — #{payload.changes_count} change(s) applied on #{payload.node}: #{Enum.join(payload.fields, ", ")}"

  defp format_summary(event, payload),
    do: "#{event} — #{inspect(payload)}"

  defp event_severity("crash_restart", _payload), do: "error"
  defp event_severity("deployment_started", _payload), do: "info"
  defp event_severity("deployment_complete", %{status: :ok}), do: "info"
  defp event_severity("deployment_complete", %{status: :error}), do: "error"
  defp event_severity("watchdog_threshold_exceeded", _payload), do: "critical"
  defp event_severity("watchdog_threshold_warning", %{action: :warning}), do: "warning"
  defp event_severity("watchdog_threshold_warning", %{action: :normalized}), do: "info"
  defp event_severity("certificate_renewed", _payload), do: "info"
  defp event_severity("certificate_valid", _payload), do: "info"
  defp event_severity("certificate_failed", _payload), do: "error"
  defp event_severity("deployment_shutdown", _payload), do: "warning"
  defp event_severity("config_changed", _payload), do: "warning"
  defp event_severity("config_change_applied", _payload), do: "info"
  defp event_severity(_event, _payload), do: "info"

  defp event_source(%{node: node}), do: to_string(node)
  defp event_source(_payload), do: "deployex"
end
