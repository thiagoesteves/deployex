defmodule Foundation.Notifications.Adapter do
  @moduledoc """
  Behaviour that every notification channel must implement.

  ## Implementing a new adapter

  1. Create a module that `@behaviour Foundation.Notifications.Adapter`.
  2. Implement `notify/3`.  Return `:ok` on success or `{:error, reason}` on
     failure — `Foundation.Notifications` will log the error automatically.
  3. Add a new clause to `Foundation.Yaml.notification_adapter/1` so the adapter
     can be selected from `deployex.yaml`.

  ### Example skeleton

      defmodule Foundation.Notifications.MyChannel do
        @behaviour Foundation.Notifications.Adapter

        alias Foundation.Yaml

        @impl true
        def notify(event, payload, %Yaml.Notification{url: url, options: options}) do
          # build and send the notification
          :ok
        end
      end

  ### Adapter-specific configuration

  Anything in the `options:` map of a notification entry is passed through
  as-is in `config.options`.  Use string keys (they come from YAML), e.g.:

      options:
        api_token: "secret"
        channel: "#alerts"

  accessed as `Map.get(options, "api_token")` inside `notify/3`.
  """

  alias Foundation.Yaml

  @doc """
  Deliver a single event notification.

  Called asynchronously by `Foundation.Notifications.notify/2` for every enabled
  adapter whose `events` list includes the given `event`.

  ## Parameters

    - `event`   — one of the atoms defined in `Foundation.Notifications` (e.g. `:crash_restart`)
    - `payload` — map with event-specific fields; keys are atoms
    - `config`  — the `Foundation.Yaml.Notification` struct for this adapter instance,
                  containing `:url`, `:options`, and so on
  """
  @callback notify(
              event :: atom(),
              payload :: map(),
              config :: Yaml.Notification.t()
            ) :: :ok | {:error, term()}
end
