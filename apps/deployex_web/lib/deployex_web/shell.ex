defmodule DeployexWeb.Shell do
  @moduledoc """
  Shell sessions for the dashboard: the host shell, and the IEx or Erlang shell of an instance.

  A session belongs to a user and a target, so a user has at most one session for each target. It outlives
  the page that opened it: the dock and the Terminal page attach to it, and it ends on `close/2`, when its
  shell exits, or at the 15-minute limit.
  """

  alias DeployexWeb.Shell.Server

  @host "host"
  @registry DeployexWeb.Shell.Registry

  defmodule Session do
    @moduledoc """
    What a page needs to show a session.
    """
    @type t :: %__MODULE__{
            id: String.t(),
            user: String.t(),
            target: String.t(),
            kind: :host_shell | :iex | :erlang_shell,
            language: String.t(),
            command: String.t(),
            started_at: DateTime.t(),
            expires_at: DateTime.t()
          }

    defstruct [:id, :user, :target, :kind, :language, :command, :started_at, :expires_at]
  end

  @doc """
  The target of the host shell. Any other target is an instance sname, or `deployex`.
  """
  @spec host() :: String.t()
  def host, do: @host

  @doc """
  Returns the user's session for the target, or starts one.
  """
  @spec open(user :: String.t(), target :: String.t()) :: {:ok, Session.t()} | {:error, term()}
  def open(user, target) do
    case lookup(user, target) do
      {:ok, _pid, session} ->
        {:ok, session}

      :error ->
        case DynamicSupervisor.start_child(DeployexWeb.Shell.Supervisor, {Server, {user, target}}) do
          {:ok, pid} -> {:ok, Server.session(pid)}
          {:error, {:already_started, pid}} -> {:ok, Server.session(pid)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Returns the user's open sessions, the oldest first.
  """
  @spec list(user :: String.t()) :: [Session.t()]
  def list(user) do
    @registry
    |> Registry.select([{{{:"$1", :_}, :_, :"$2"}, [{:==, :"$1", user}], [:"$2"]}])
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  @doc """
  Subscribes the caller to the session's output, and returns what it printed so far.

  The caller then gets `{:shell_output, id, data}` for each new chunk and `{:shell_closed, id}` at the end.
  """
  @spec attach(user :: String.t(), target :: String.t()) :: {:ok, Session.t(), binary()} | :error
  def attach(user, target) do
    with {:ok, pid, session} <- lookup(user, target) do
      :ok = Phoenix.PubSub.subscribe(DeployexWeb.PubSub, topic(session.id))
      {:ok, session, Server.scrollback(pid)}
    end
  end

  @doc """
  Stops following a session, which keeps running.
  """
  @spec detach(Session.t()) :: :ok
  def detach(%Session{id: id}), do: Phoenix.PubSub.unsubscribe(DeployexWeb.PubSub, topic(id))

  @doc """
  Sends keys to the session's shell.
  """
  @spec send_keys(user :: String.t(), target :: String.t(), keys :: String.t()) :: :ok
  def send_keys(user, target, keys), do: with_server(user, target, &Server.send_keys(&1, keys))

  @doc """
  Sets the terminal size of the session's shell.
  """
  @spec resize(String.t(), String.t(), pos_integer(), pos_integer()) :: :ok
  def resize(user, target, rows, cols),
    do: with_server(user, target, &Server.resize(&1, rows, cols))

  @doc """
  Ends the session and its shell.
  """
  @spec close(user :: String.t(), target :: String.t()) :: :ok
  def close(user, target), do: with_server(user, target, &Server.close/1)

  @doc false
  @spec topic(id :: String.t()) :: String.t()
  def topic(id), do: "deployex::shell::#{id}"

  @doc false
  def via(user, target), do: {:via, Registry, {@registry, {user, target}}}

  defp lookup(user, target) do
    case Registry.lookup(@registry, {user, target}) do
      [{pid, %Session{} = session}] -> {:ok, pid, session}
      _ -> :error
    end
  end

  defp with_server(user, target, fun) do
    case lookup(user, target) do
      {:ok, pid, _session} -> fun.(pid)
      :error -> :ok
    end
  end
end
