defmodule Foundation.Notifications.Supervisor do
  @moduledoc """
  Supervisor that owns one `Foundation.Notifications.Worker` per notification
  channel defined in the `notifications:` YAML list.

  Children are built from `Application.get_env(:foundation, :notifications, [])`
  at startup, so the number and type of workers matches the runtime configuration
  loaded by `Foundation.ConfigProvider.Env.Config`.

  Each worker is assigned a unique child ID based on its position in the list,
  so multiple entries with the same adapter type are all started correctly.
  """

  use Supervisor

  alias Foundation.Notifications.Worker

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(args \\ []) do
    name = Keyword.get(args, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(_args) do
    children =
      :foundation
      |> Application.get_env(:notifications, [])
      |> Enum.with_index()
      |> Enum.map(fn {config, index} ->
        Supervisor.child_spec({Worker, config}, id: {Worker, index})
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
