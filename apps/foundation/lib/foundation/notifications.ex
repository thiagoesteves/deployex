defmodule Foundation.Notifications do
  @moduledoc """
  Dispatches deployment lifecycle events to configured external notification channels.

  `Foundation.Notifications.notify/2` is a fire-and-forget call: it reads the
  adapter list from the `:foundation` application environment (populated at boot by
  `Foundation.ConfigProvider.Env.Config` from `deployex.yaml`), filters to adapters
  that are enabled and subscribed to the event, then dispatches each delivery in a
  separate `Task.Supervisor` child so callers are never blocked.

  ## Supported events

  | Event atom                      | Trigger                                                   | Payload keys                                                            |
  |---------------------------------|-----------------------------------------------------------|-------------------------------------------------------------------------|
  | `:crash_restart`                | Monitored app crashed and is being restarted              | `node`, `sname`, `name`, `language`, `crash_restart_count`             |
  | `:deployment_started`           | New deployment was initiated for an sname                 | `node`, `sname`, `version`                                              |
  | `:deployment_complete`          | Hot-upgrade finished (success or failure)                 | `node`, `sname`, `status` (`:ok`/`:error`), `message`                  |
  | `:watchdog_threshold_exceeded`  | Watchdog exceeded resource threshold and restarted an app | `node`, `sname`, `type`, `current_percentage`, `restart_threshold_percent` |
  | `:certificate_renewed`          | TLS certificate was successfully renewed                  | `app_name`, `domains`                                                   |
  | `:certificate_failed`           | TLS certificate renewal failed                            | `app_name`, `domains`, `reason`                                         |

  ## Available adapters

  | YAML value    | Module                                | Description                            |
  |---------------|---------------------------------------|----------------------------------------|
  | `"webhook"`   | `Foundation.Notifications.Webhook`   | Generic HTTP POST with a JSON body     |
  | `"slack"`     | `Foundation.Notifications.Slack`     | Slack Incoming Webhook message         |
  | `"pagerduty"` | `Foundation.Notifications.PagerDuty` | PagerDuty Events API v2 incident       |

  See each adapter's module documentation for its specific configuration options.

  ## Configuration (deployex.yaml)

  Multiple adapters can run in parallel.  Each entry is independent: a different
  channel can subscribe to a different subset of events.

      notifications:
        # Slack: all events to #deployex-alerts
        - adapter: "slack"
          url: "https://hooks.slack.com/services/T.../B.../..."
          enabled: true
          events:
            - "crash_restart"
            - "deployment_complete"
            - "watchdog_threshold_exceeded"
          options:
            username: "DeployEx"
            icon_emoji: ":rocket:"

        # PagerDuty: only critical events that need on-call intervention
        - adapter: "pagerduty"
          enabled: true
          events:
            - "crash_restart"
            - "watchdog_threshold_exceeded"
            - "certificate_failed"
          options:
            routing_key: "abc123def456..."

        # Generic webhook: send all events to an internal audit service
        - adapter: "webhook"
          url: "https://internal.example.com/hooks/deployex"
          enabled: true
          events:
            - "crash_restart"
            - "deployment_started"
            - "deployment_complete"
            - "watchdog_threshold_exceeded"
            - "certificate_renewed"
            - "certificate_failed"

  ## Adding a new adapter

  Implement `Foundation.Notifications.Adapter` and add a new clause to
  `Foundation.Yaml.notification_adapter/1`.  See `Foundation.Notifications.Adapter`
  for a step-by-step guide and skeleton implementation.
  """

  require Logger

  @doc """
  Delivers `event` with `payload` to every enabled, subscribed notification adapter.

  Returns `:ok` immediately; delivery happens asynchronously.  Adapter errors are
  logged but never re-raised.
  """
  @spec notify(event :: atom(), payload :: map()) :: :ok
  def notify(event, payload) do
    :foundation
    |> Application.get_env(:notifications, [])
    |> Enum.filter(&(&1.enabled and event in &1.events))
    |> Enum.each(fn config ->
      Task.Supervisor.start_child(Foundation.TaskSupervisor, fn ->
        case config.adapter.notify(event, payload, config) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error(
              "Notification adapter #{inspect(config.adapter)} failed for event=#{event} reason=#{inspect(reason)}"
            )
        end
      end)
    end)
  end
end
