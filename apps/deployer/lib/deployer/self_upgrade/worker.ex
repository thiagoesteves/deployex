defmodule Deployer.SelfUpgrade.Worker do
  @moduledoc """
  Reconciles the running DeployEx version toward the desired version published by IaC.
  """

  use GenServer
  require Logger

  alias Deployer.SelfUpgrade.Executor
  alias Deployer.SelfUpgrade.Source

  defstruct interval_ms: 60_000, last_failed: nil, timer: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Synchronous reconcile. Returns :ok | :noop | {:error, reason}."
  @spec reconcile(GenServer.server()) :: :ok | :noop | {:error, any()}
  def reconcile(server \\ __MODULE__), do: GenServer.call(server, :reconcile)

  @impl true
  def init(opts) do
    state = %__MODULE__{
      interval_ms: Keyword.get(opts, :interval_ms, 60_000)
    }

    {:ok, schedule(state)}
  end

  @impl true
  def handle_call(:reconcile, _from, state) do
    {result, state} = do_reconcile(state)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_result, state} = do_reconcile(state)
    {:noreply, schedule(state)}
  end

  defp schedule(%{interval_ms: :never} = state), do: state

  defp schedule(state) do
    timer = Process.send_after(self(), :tick, state.interval_ms)
    %{state | timer: timer}
  end

  defp running_version, do: Application.spec(:foundation, :vsn) |> to_string()

  defp do_reconcile(state) do
    case Source.desired_version() do
      {:ok, version} ->
        reconcile_version(version, state)

      :none ->
        {:noop, state}

      {:error, reason} ->
        Logger.warning("Self-upgrade: source error #{inspect(reason)}")
        {:noop, state}
    end
  end

  defp reconcile_version(version, state) do
    cond do
      version == running_version() -> {:noop, %{state | last_failed: nil}}
      version == state.last_failed -> {:noop, state}
      true -> upgrade(version, state)
    end
  end

  defp upgrade(version, state) do
    emit(:started, %{version: version})

    case Executor.hot_upgrade(version) do
      :ok ->
        emit(:hot_ok, %{version: version})
        {:ok, %{state | last_failed: nil}}

      {:error, reason} ->
        emit(:hot_failed, %{version: version, reason: reason})

        Logger.error(
          "Self-upgrade: hot upgrade to #{version} failed: #{inspect(reason)}. Staying on current version."
        )

        {{:error, reason}, %{state | last_failed: version}}
    end
  end

  # Telemetry and PubSub are observability only. A failure here must never crash
  # the worker or affect the upgrade that already ran.
  defp emit(event, meta) do
    :telemetry.execute([:deployer, :self_upgrade, event], %{count: 1}, meta)
    Phoenix.PubSub.broadcast(Deployer.PubSub, "self_upgrade", {:self_upgrade, event, meta})
  rescue
    error -> Logger.warning("Self-upgrade: emit #{inspect(event)} failed: #{inspect(error)}")
  end
end
