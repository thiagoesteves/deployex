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

  use DynamicSupervisor

  alias Foundation.Notifications.Worker

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 20)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec start_notification_worker(config :: Worker.t()) ::
          {:ok, pid} | {:error, pid(), :already_started}
  def start_notification_worker(config) do
    spec = %{
      id: Worker,
      start: {Worker, :start_link, [config]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec stop_all_notification_workers() :: :ok
  def stop_all_notification_workers do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} -> DynamicSupervisor.terminate_child(__MODULE__, pid) end)

    :ok
  end
end
