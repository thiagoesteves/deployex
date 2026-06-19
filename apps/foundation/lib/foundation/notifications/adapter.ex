defmodule Foundation.Notifications.Adapter do
  @moduledoc """
  Behaviour that every notification channel must implement.

  ## Implementing a new adapter

  1. Create a module that `@behaviour Foundation.Notifications.Adapter`.
  2. Implement `notify/3`.  Return `:ok` on success or `{:error, reason}` on
     failure — `Foundation.Notifications.Worker` will log the error automatically.
  3. Add a new clause to the private `notification_adapter/1` in `Foundation.Yaml` so the adapter
     can be selected from `deployex.yaml`.

  ### Example skeleton

      defmodule Foundation.Notifications.MyChannel do
        @behaviour Foundation.Notifications.Adapter

        alias Foundation.Notifications.Worker

        @impl true
        def notify(event, payload, %Worker{url: url, options: options}) do
          # build and send the notification
          :ok
        end
      end

  ### Adapter-specific configuration

  Anything in the `options:` map of a notification entry is passed through
  in `config.options` with keys converted to atoms at parse time, e.g.:

      options:
        api_token: "secret"
        channel: "#alerts"

  accessed as `Map.get(options, :api_token)` inside `notify/3`.

  ## Supported events and payload fields

  | Event                          | Payload keys                                                                                   |
  |--------------------------------|-----------------------------------------------------------------------------------------------|
  | `"crash_restart"`              | `node`, `sname`, `name`, `language`, `crash_restart_count`                                   |
  | `"deployment_started"`         | `node`, `sname`, `version`                                                                    |
  | `"deployment_complete"`        | `node`, `sname`, `status` (`:ok`/`:error`), `message`                                        |
  | `"deployment_shutdown"`        | `node`, `sname`                                                                               |
  | `"watchdog_threshold_exceeded"`| `node`, `type`, `current_percentage`, `restart_threshold_percent`                             |
  | `"watchdog_threshold_warning"` | `node`, `type`, `current_percentage`, `warning_threshold_percent`, `action` (`:warning`/`:normalized`) |
  | `"certificate_renewed"`        | `app_name`, `domains`                                                                         |
  | `"certificate_failed"`         | `app_name`, `domains`, `reason`                                                               |
  | `"config_changed"`             | `node`, `changes_count`, `fields`                                                             |
  | `"config_change_applied"`      | `node`, `changes_count`, `fields`                                                             |
  """

  alias Foundation.Notifications.Worker

  @doc """
  Deliver a single event notification.

  Called asynchronously by `Foundation.Notifications.notify/2` for every enabled
  adapter whose `events` list includes the given `event`.

  ## Parameters

    - `event`   — one of the strings defined in `Foundation.Notifications` (e.g. `"crash_restart"`)
    - `payload` — map with event-specific fields; keys are atoms
    - `config`  — the `Foundation.Notifications.Worker` struct for this adapter instance,
                  containing `:url`, `:options`, and so on
  """
  @callback notify(event :: String.t(), payload :: map(), config :: Worker.t()) ::
              :ok | {:error, term()}
end
