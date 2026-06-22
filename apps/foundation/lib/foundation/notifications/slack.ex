defmodule Foundation.Notifications.Slack do
  @moduledoc """
  Notification adapter that delivers events to a Slack channel via Incoming Webhooks.

  ## How it works

  Each event is formatted into a human-readable Slack message and posted as an HTTP
  POST to the configured Incoming Webhook URL.  The URL already encodes the target
  workspace and channel, so no additional auth header is needed.

  ## Worker configuration

      notifications:
        - adapter: "slack"
          url: "https://hooks.slack.com/services/T00/B00/token"
          enabled: true
          events:
            - "crash_restart"
            - "deployment_started"
            - "deployment_complete"
            - "deployment_shutdown"
            - "watchdog_threshold_exceeded"
            - "watchdog_threshold_warning"
            - "certificate_renewed"
            - "certificate_valid"
            - "certificate_failed"
            - "config_changed"
            - "config_change_applied"
          options:
            username: "DeployEx"        # optional, default: "DeployEx"
            icon_emoji: ":rocket:"      # optional, default: ":robot_face:"

  ## Setting up a Slack Incoming Webhook

  1. Go to https://api.slack.com/apps → *Create New App* → *From scratch*.
  2. Under *Features*, choose *Incoming Webhooks* and activate them.
  3. Click *Add New Webhook to Workspace*, pick a channel, and copy the URL.
  4. Paste that URL as the `url:` value in `deployex.yaml`.

  ## Message format

  Messages use Slack's `mrkdwn` formatting.  Examples:

      🚨 *crash_restart* — `myapp-1` on `myapp@prod-1`
      Crash count: *3*

      ✅ *deployment_complete* — `myapp-1` on `myapp@prod-1`
      Status: *ok* — Hot upgrade applied successfully!

  ## Supported events

  | Event                           | Emoji | Description                                           |
  |---------------------------------|-------|-------------------------------------------------------|
  | `crash_restart`                 | 🚨    | App crashed and was restarted                         |
  | `deployment_started`            | 🚀    | New deployment initiated                              |
  | `deployment_complete` (ok)      | ✅    | Deployment finished successfully                      |
  | `deployment_complete` (error)   | ❌    | Deployment finished with error                        |
  | `deployment_shutdown`           | 🛑    | App force-terminated (will restart shortly)           |
  | `watchdog_threshold_exceeded`   | ⚠️    | Resource threshold crossed; app restarted             |
  | `watchdog_threshold_warning`    | 🔶/✅ | Resource crossed warning threshold or normalized      |
  | `certificate_renewed`           | 🔒    | TLS certificate successfully renewed                  |
  | `certificate_failed`            | 🔓    | TLS certificate renewal failed                        |
  | `config_changed`                | ⚙️    | Upgradable config change detected in YAML             |
  | `config_change_applied`         | ✅    | Pending config changes successfully applied           |
  """

  @behaviour Foundation.Notifications.Adapter

  require Logger

  alias Foundation.Notifications.Worker

  @default_username "DeployEx"
  @default_icon_emoji ":robot_face:"

  @impl true
  @spec notify(event :: String.t(), payload :: map(), config :: Worker.t()) ::
          :ok | {:error, term()}
  def notify(event, payload, %Worker{url: url, options: options}) do
    body =
      Jason.encode!(%{
        text: format_message(event, payload),
        username: options[:username] || @default_username,
        icon_emoji: options[:icon_emoji] || @default_icon_emoji
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
      "Slack notification failed for event=#{event} url=#{url} status=#{status} body=#{body}"
    )

    {:error, {:http_error, status}}
  end

  defp handle_response({:error, reason}, event, url) do
    Logger.error(
      "Slack notification error for event=#{event} url=#{url} reason=#{inspect(reason)}"
    )

    {:error, reason}
  end

  defp format_message("crash_restart", payload) do
    """
    🚨 *crash_restart* — `#{payload.sname}` on `#{payload.node}`
    Crash count: *#{payload.crash_restart_count}*\
    """
  end

  defp format_message("deployment_started", payload) do
    """
    🚀 *deployment_started* — `#{payload.sname}` on `#{payload.node}`
    Version: *#{payload.version}*\
    """
  end

  defp format_message("deployment_complete", %{status: :ok} = payload) do
    """
    ✅ *deployment_complete* — `#{payload.sname}` on `#{payload.node}`
    Status: *ok* — #{payload.message}\
    """
  end

  defp format_message("deployment_complete", %{status: :error} = payload) do
    """
    ❌ *deployment_complete* — `#{payload.sname}` on `#{payload.node}`
    Status: *error* — #{payload.message}\
    """
  end

  defp format_message("watchdog_threshold_exceeded", payload) do
    """
    ⚠️ *watchdog_threshold_exceeded* — `#{payload.node}`
    Resource: *#{payload.type}* at *#{payload.current_percentage}%* (threshold: #{payload.restart_threshold_percent}%)\
    """
  end

  defp format_message("watchdog_threshold_warning", %{action: :warning} = payload) do
    """
    🔶 *watchdog_threshold_warning* — `#{payload.node}`
    Resource: *#{payload.type}* at *#{payload.current_percentage}%* (warning: #{payload.warning_threshold_percent}%)\
    """
  end

  defp format_message("watchdog_threshold_warning", %{action: :normalized} = payload) do
    """
    ✅ *watchdog_threshold_warning* — `#{payload.node}` normalized
    Resource: *#{payload.type}* back to *#{payload.current_percentage}%* (below #{payload.warning_threshold_percent}%)\
    """
  end

  defp format_message("certificate_renewed", payload) do
    """
    🔒 *certificate_renewed* — `#{payload.app_name}`
    Domains: #{Enum.join(payload.domains, ", ")}\
    """
  end

  defp format_message("certificate_failed", payload) do
    """
    🔓 *certificate_failed* — `#{payload.app_name}`
    Domains: #{Enum.join(payload.domains, ", ")}
    Reason: #{payload.reason}\
    """
  end

  defp format_message("deployment_shutdown", payload) do
    """
    🛑 *deployment_shutdown* — `#{payload.sname}` on `#{payload.node}`
    `#{payload.sname}` was force-terminated and will restart shortly.\
    """
  end

  defp format_message("config_changed", payload) do
    """
    ⚙️ *config_changed* — `#{payload.node}`
    #{payload.changes_count} change(s) detected: #{Enum.join(payload.fields, ", ")}\
    """
  end

  defp format_message("config_change_applied", payload) do
    """
    ✅ *config_change_applied* — `#{payload.node}`
    #{payload.changes_count} change(s) applied: #{Enum.join(payload.fields, ", ")}\
    """
  end

  defp format_message(event, payload) do
    "ℹ️ *#{event}*\n#{inspect(payload)}"
  end
end
