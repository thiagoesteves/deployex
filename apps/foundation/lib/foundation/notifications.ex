defmodule Foundation.Notifications do
  @moduledoc """
  Dispatches deployment lifecycle events to configured external notification channels.

  `Foundation.Notifications.notify/2` broadcasts an event to a per-event
  `Foundation.PubSub` topic (e.g. `"deployex::notifications::crash_restart"`).
  Each `Foundation.Notifications.Worker` — one per entry in the `notifications:`
  YAML list — subscribes only to the topics matching its `events` list at startup,
  so PubSub routing handles delivery without any filtering in the worker.  This means:

  - **Callers are never blocked** — `Phoenix.PubSub.broadcast/3` returns immediately.
  - **Channels are isolated** — a slow or crashing adapter only affects its own worker.
  - **Workers are supervised** — `Foundation.Notifications.Supervisor` restarts a
    crashed worker automatically.

  ## Supported events

  | Event atom                       | Trigger                                                    | Payload keys                                                                |
  |----------------------------------|------------------------------------------------------------|-----------------------------------------------------------------------------|
  | `:crash_restart`                 | Monitored app crashed and is being restarted               | `node`, `sname`, `name`, `language`, `crash_restart_count`                 |
  | `:deployment_started`            | New deployment was initiated for an sname                  | `node`, `sname`, `version`                                                  |
  | `:deployment_complete`           | Hot-upgrade finished (success or failure)                  | `node`, `sname`, `status` (`:ok`/`:error`), `message`                      |
  | `:watchdog_threshold_exceeded`   | Watchdog exceeded a resource threshold and restarted an app| `node`, `sname`, `type`, `current_percentage`, `restart_threshold_percent` |
  | `:certificate_renewed`           | TLS certificate was successfully renewed                   | `app_name`, `domains`                                                       |
  | `:certificate_failed`            | TLS certificate renewal failed                             | `app_name`, `domains`, `reason`                                             |

  ## Available adapters

  | YAML value    | Module                                | Description                           |
  |---------------|---------------------------------------|---------------------------------------|
  | `"webhook"`   | `Foundation.Notifications.Webhook`   | Generic HTTP POST with a JSON body    |
  | `"slack"`     | `Foundation.Notifications.Slack`     | Slack Incoming Webhook message        |
  | `"pagerduty"` | `Foundation.Notifications.PagerDuty` | PagerDuty Events API v2 incident      |

  ## Configuration (deployex.yaml)

  Multiple adapters can run in parallel.  Each entry is independent and subscribes
  to its own subset of events.

      notifications:
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

        - adapter: "pagerduty"
          enabled: true
          events:
            - "crash_restart"
            - "watchdog_threshold_exceeded"
            - "certificate_failed"
          options:
            routing_key: "abc123def456..."

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
  for a step-by-step guide and a skeleton implementation.
  """

  @topic_prefix "deployex::notifications"

  @doc """
  Returns the PubSub topic for a specific event.

  Each `Foundation.Notifications.Worker` subscribes to `topic(event)` for
  every event in its list.  `notify/2` broadcasts to the same per-event topic,
  so PubSub routing delivers the message only to workers that subscribed to it.

  ## Example

      iex> Foundation.Notifications.topic(:crash_restart)
      "deployex::notifications::crash_restart"
  """
  @spec topic(event :: atom()) :: String.t()
  def topic(event), do: "#{@topic_prefix}::#{event}"

  @doc """
  Broadcasts `event` with `payload` to all workers subscribed to that event.

  Returns `:ok` immediately; delivery to each adapter happens asynchronously
  inside the respective `Foundation.Notifications.Worker` process.
  """
  @spec notify(event :: atom(), payload :: map()) :: :ok
  def notify(event, payload) do
    Phoenix.PubSub.broadcast(Foundation.PubSub, topic(event), {event, payload})
  end
end
