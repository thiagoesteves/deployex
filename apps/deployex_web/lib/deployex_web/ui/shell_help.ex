defmodule DeployexWeb.UI.ShellHelp do
  @moduledoc """
  The shortcuts panel next to a shell, on the Terminal page and in the dock. The IEx and Erlang shells are
  remote shells into a release, which has no Mix, no sources and no docs, so the list holds what works there.
  """
  use Phoenix.Component

  @shortcuts %{
    iex: [
      {"runtime_info", "memory, limits and applications of the node"},
      {"i value", "what a value is, like a pid"},
      {"exports Module", "the public functions of a module"},
      {"Process.whereis(Name)", "the pid of a named process"},
      {":sys.get_state(pid)", "the state of a GenServer"},
      {"v(n)", "the result of expression n"},
      {"clear", "clear the screen"},
      {"Ctrl+G, then c", "the user switch command, and back"}
    ],
    erlang_shell: [
      {"i().", "the processes of the node"},
      {"regs().", "the registered processes"},
      {"memory().", "the memory use of the node"},
      {"sys:get_state(Pid).", "the state of a gen_server"},
      {"b().", "the variable bindings"},
      {"f(X).", "forget the binding of X, f(). forgets all"},
      {"v(N).", "the result of expression N"},
      {"Ctrl+G, then c", "the user switch command, and back"}
    ],
    host_shell: [
      {"Ctrl+B d", "detach, the session keeps running"},
      {"Ctrl+B c", "new window"},
      {"Ctrl+B n", "next window"},
      {"Ctrl+B %", "split side by side"},
      {"Ctrl+B [", "scroll mode, q to leave"},
      {"clear", "clear the screen"}
    ]
  }

  attr :kind, :atom, required: true, doc: ":iex, :erlang_shell or :host_shell"
  attr :class, :any, default: nil, doc: "more classes, like dx-help-dock in the dock"

  def help(assigns) do
    assigns = assign(assigns, :shortcuts, Map.fetch!(@shortcuts, assigns.kind))

    ~H"""
    <aside class={["dx-help", @class]} aria-label="Shortcuts" tabindex="0">
      <h2 class="text-sm font-bold">{title(@kind)}</h2>
      <p :if={@kind == :host_shell} class="text-[0.8125rem] font-semibold text-warning-text">
        This shell runs as the deployex user. It can read the release and the logs of every app on this host.
      </p>
      <p :if={@kind == :erlang_shell} class="text-[0.8125rem] font-semibold text-warning-text">
        Do not run q(). In this remote shell it stops the app.
      </p>
      <div>
        <div :for={{command, description} <- @shortcuts} class="dx-sc">
          <code>{command}</code><span>{description}</span>
        </div>
      </div>
      <p :if={@kind != :host_shell} class="dx-muted text-xs">
        A release has no Mix, sources or docs, so recompile, r, c and h do not work here.
      </p>
    </aside>
    """
  end

  defp title(:iex), do: "IEx shortcuts"
  defp title(:erlang_shell), do: "Erlang shell shortcuts"
  defp title(:host_shell), do: "tmux keys"
end
