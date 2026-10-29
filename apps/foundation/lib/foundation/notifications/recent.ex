defmodule Foundation.Notifications.Recent do
  @moduledoc """
  The last events that this host sent, for the dashboard's notifications bell.

  `Foundation.Notifications.Recent.Server` keeps them in memory, so the list starts empty after a DeployEx
  restart. Events from connected DeployEx nodes are not included, each node reports its own.
  """

  alias Foundation.Notifications.Recent.Server

  @topic "deployex::recent_notifications"

  @type t :: %__MODULE__{
          id: pos_integer(),
          at: DateTime.t(),
          event: String.t(),
          payload: map()
        }

  defstruct [:id, :at, :event, payload: %{}]

  @doc """
  Returns the kept events, newest first.
  """
  @spec list() :: [t()]
  def list, do: Server.list()

  @doc """
  Subscribes the caller to each new event, as `{:recent_notification, %Recent{}}`.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Foundation.PubSub, @topic)

  @doc false
  @spec topic() :: String.t()
  def topic, do: @topic
end
