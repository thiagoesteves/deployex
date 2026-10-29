defmodule DeployexWeb.DockLive do
  @moduledoc """
  The dock: a panel at the bottom of every page with tabs for logs and shell sessions.

  It is a sticky nested LiveView in the layout, so it stays open with its tabs while the user moves
  between pages. The shell sessions belong to `DeployexWeb.Shell`, the same ones the Terminal page shows.
  A page opens a tab with the `dx:dock-open` window event, which the `Dock` hook passes on.
  """
  use DeployexWeb, :live_view

  alias DeployexWeb.Shell
  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Tags
  alias Foundation.Catalog
  alias Sentinel.Logs

  @log_minutes 30
  @log_cap 500
  @types ["stdout", "stderr"]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :active_tab, Enum.find(assigns.tabs, &(&1.id == assigns.active)))

    ~H"""
    <div id="dock" phx-hook="Dock">
      <section :if={@tabs != []} class="dx-dock" aria-label="Dock" data-dock-panel>
        <button
          type="button"
          class="dx-dock-grip"
          data-dock-grip
          aria-label="Resize the dock. Drag it, or use the up and down arrow keys."
          title="Drag to resize"
        ></button>
        <div class="dx-dock-bar">
          <div class="dx-dock-tabs" role="group" aria-label="Dock sessions">
            <div
              :for={tab <- @tabs}
              class={[
                "dx-dtab",
                tab.kind == :shell && "dx-dtab-term",
                tab.id == @active && "dx-dtab-on"
              ]}
            >
              <button
                id={"dock-tab-#{tab.id}"}
                type="button"
                class="dx-dtab-sel"
                aria-pressed={to_string(tab.id == @active)}
                phx-click="select"
                phx-value-id={tab.id}
              >
                <Tags.lang name={tab.language} small />{tab.target}<span class="dx-dtab-kind">{tab.label}</span>
              </button>
              <button
                id={"dock-close-#{tab.id}"}
                type="button"
                class="dx-dtab-x"
                aria-label={close_label(tab)}
                title={close_label(tab)}
                phx-click="close-tab"
                phx-value-id={tab.id}
              >
                <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-[13px]" />
              </button>
            </div>
          </div>
          <div class="dx-dock-ctl">
            <span
              :if={@active_tab && @active_tab.kind == :shell}
              class="dx-muted mr-2 text-[12.5px] whitespace-nowrap"
            >
              Closes in
              <b
                id={"dock-countdown-#{@active_tab.id}"}
                class="dx-mono text-(--dx-base-content)"
                phx-hook="Countdown"
                data-expires={DateTime.to_iso8601(@active_tab.session.expires_at)}
              ></b>
            </span>
            <button
              type="button"
              class="dx-ghost"
              data-dock="taller"
              aria-label="Make the dock taller"
              title="Taller"
            >
              <Icons.icon name="arrow-up" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              type="button"
              class="dx-ghost"
              data-dock="shorter"
              aria-label="Make the dock shorter"
              title="Shorter"
            >
              <Icons.icon name="arrow-down" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              type="button"
              class="dx-ghost"
              data-dock="minimize"
              aria-label="Minimize the dock"
              title="Minimize"
            >
              <Icons.icon name="chevron-down" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              type="button"
              class="dx-ghost"
              data-dock="maximize"
              aria-pressed="false"
              aria-label="Expand the dock"
              title="Full size"
            >
              <Icons.icon name="arrows-out" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              id="dock-close"
              type="button"
              class="dx-ghost"
              aria-label="Close the dock and end its sessions"
              title="Close the dock"
              phx-click="close"
            >
              <Icons.icon name="x-mark" stroke="2" class="dx-ico size-4" />
            </button>
          </div>
        </div>
        <div :if={@asking_close} class="dx-ask" role="group" aria-label="Confirm closing the dock">
          <span class="flex-[1_1_320px]">
            <b>Close the dock?</b> It ends {shell_count(@tabs)} and closes every tab.
          </span>
          <button
            id="dock-close-confirm"
            type="button"
            class="dx-btn dx-btn-danger"
            phx-click="confirm-close"
          >
            End and close
          </button>
          <button type="button" class="dx-btn" phx-click="cancel-close">Cancel</button>
        </div>
        <div class="dx-dock-body">
          <%= if @active_tab && @active_tab.kind == :logs do %>
            <div class="dx-k-head">
              <span class="dx-muted dx-mono text-xs">{logs_subtitle(@active_tab)} · last 30 minutes, then live</span>
              <div class="flex items-center gap-1.5">
                <.link
                  class="dx-link mr-1.5 text-[12.5px] font-semibold"
                  navigate={~p"/logs/live?#{logs_query(@active_tab)}"}
                >
                  History and filters in Logs
                </.link>
                <button
                  :for={type <- ["stdout", "stderr"]}
                  id={"dock-stream-#{type}"}
                  type="button"
                  class="dx-k-tog"
                  aria-pressed={to_string(type in @active_tab.types)}
                  phx-click="toggle-stream"
                  phx-value-type={type}
                >
                  <span style={type == "stderr" && "color: var(--dx-error-text)"}>{type}</span>
                </button>
              </div>
            </div>
            <div
              id="dock-log"
              class="dx-k-log"
              role="log"
              aria-live="off"
              aria-label="Log lines"
              tabindex="0"
              phx-hook="ScrollBottom"
            >
              <div id="dock-lines" phx-update="stream">
                <div
                  :for={{dom_id, line} <- @streams.lines}
                  id={dom_id}
                  class="dx-k-row"
                  style={"grid-template-columns: #{if line.many, do: "96px 160px 54px minmax(0, 1fr)", else: "96px 54px minmax(0, 1fr)"}"}
                >
                  <span class="dx-muted">{Calendar.strftime(line.at, "%H:%M:%S.%f")
                  |> String.slice(0, 12)}</span>
                  <span :if={line.many} class="truncate">{line.source}</span>
                  <span style={"color: #{if line.type == "stderr", do: "var(--dx-error-text)", else: "var(--dx-muted)"}"}>
                    {line.type}
                  </span>
                  <span class="dx-k-msg" style={"color: #{message_color(line)}"} phx-no-format>{line.text}</span>
                </div>
              </div>
              <p :if={@active_tab.empty} class="dx-muted p-3.5 text-[13px]">
                No lines for these streams.
              </p>
            </div>
          <% end %>
          <div :if={@active_tab && @active_tab.kind == :shell} class="dx-k-term">
            <div
              id={"dock-xterm-#{@active_tab.session.id}"}
              class="dx-xterm flex-1"
              phx-hook="XTerm"
              phx-update="ignore"
              data-target={@active_tab.target}
              data-focus
              role="log"
              aria-label={"Shell output of #{@active_tab.target}"}
            >
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:user, session["user"])
     |> assign(:tabs, [])
     |> assign(:active, nil)
     |> assign(:attached, nil)
     |> assign(:asking_close, false)
     |> stream(:lines, []), layout: false}
  end

  @impl true
  def handle_event("open", %{"kind" => "logs", "target" => target} = params, socket) do
    id = "logs:#{target}"
    tabs = socket.assigns.tabs

    tabs =
      if Enum.any?(tabs, &(&1.id == id)) do
        tabs
      else
        snames = log_snames(target, params["app"])
        whole_app = target == params["app"] and target != "deployex"
        for sname <- snames, type <- @types, do: Logs.subscribe_for_new_logs(sname, type)

        tab = %{
          id: id,
          kind: :logs,
          target: target,
          label: "Logs",
          language: language(params["app"] || target),
          snames: snames,
          whole_app: whole_app,
          types: @types,
          buffer: read_logs(snames, @types, whole_app),
          empty: false
        }

        tabs ++ [tab]
      end

    {:noreply, socket |> assign(:tabs, tabs) |> activate(id)}
  end

  def handle_event(
        "open",
        %{"kind" => "shell", "target" => target} = params,
        %{assigns: %{user: user}} = socket
      ) do
    id = "shell:#{target}"

    if Enum.any?(socket.assigns.tabs, &(&1.id == id)) do
      {:noreply, activate(socket, id)}
    else
      case Shell.open(user, target) do
        {:ok, session} ->
          tab = %{
            id: id,
            kind: :shell,
            target: target,
            label: if(session.kind == :iex, do: "IEx", else: "Erlang shell"),
            language: language(params["app"] || target),
            session: session
          }

          {:noreply, socket |> update(:tabs, &(&1 ++ [tab])) |> activate(id)}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Could not open a shell on #{target}: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("select", %{"id" => id}, socket), do: {:noreply, activate(socket, id)}

  def handle_event("close-tab", %{"id" => id}, socket), do: {:noreply, close_tab(socket, id)}

  def handle_event("close", _params, %{assigns: %{tabs: tabs}} = socket) do
    if Enum.any?(tabs, &(&1.kind == :shell)) do
      {:noreply, assign(socket, :asking_close, true)}
    else
      {:noreply, close_all(socket)}
    end
  end

  def handle_event("confirm-close", _params, socket), do: {:noreply, close_all(socket)}

  def handle_event("cancel-close", _params, socket),
    do: {:noreply, assign(socket, :asking_close, false)}

  def handle_event("toggle-stream", %{"type" => type}, %{assigns: %{active: active}} = socket)
      when type in @types do
    socket =
      update_tab(socket, active, fn tab ->
        types = if type in tab.types, do: List.delete(tab.types, type), else: tab.types ++ [type]
        %{tab | types: types}
      end)

    {:noreply, show_logs(socket)}
  end

  def handle_event(
        "shell-keys",
        %{"target" => target, "keys" => keys},
        %{assigns: %{user: user}} = socket
      ) do
    Shell.send_keys(user, target, keys)
    {:noreply, socket}
  end

  def handle_event("shell-resize", %{"target" => target, "rows" => rows, "cols" => cols}, socket)
      when is_integer(rows) and is_integer(cols) do
    Shell.resize(socket.assigns.user, target, rows, cols)
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:logs_new_data, sname, type, message},
        %{assigns: %{tabs: tabs, active: active}} = socket
      ) do
    socket =
      Enum.reduce(tabs, socket, fn
        %{kind: :logs, snames: snames} = tab, socket ->
          if sname in snames do
            lines = lines(sname, type, [message], tab.whole_app)

            socket =
              update_tab(
                socket,
                tab.id,
                &%{&1 | buffer: Enum.take(Enum.reverse(lines) ++ &1.buffer, @log_cap)}
              )

            if tab.id == active and type in tab.types do
              socket
              |> stream(:lines, lines, limit: -@log_cap)
              |> update_tab(tab.id, &%{&1 | empty: false})
            else
              socket
            end
          else
            socket
          end

        _tab, socket ->
          socket
      end)

    {:noreply, socket}
  end

  def handle_info(
        {:shell_output, id, data},
        %{assigns: %{attached: %{id: id, target: target}}} = socket
      ),
      do: {:noreply, push_event(socket, "shell-output-#{target}", %{data: data})}

  def handle_info({:shell_closed, id}, %{assigns: %{tabs: tabs}} = socket) do
    case Enum.find(tabs, &(&1.kind == :shell and &1.session.id == id)) do
      nil -> {:noreply, socket}
      tab -> {:noreply, close_tab(socket, tab.id, false)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp activate(socket, id) do
    socket
    |> assign(:active, id)
    |> assign(:asking_close, false)
    |> attach()
    |> show_logs()
  end

  # Follows the active shell session, and stops following the one before. Both keep running
  defp attach(%{assigns: %{tabs: tabs, active: active, attached: attached}} = socket) do
    tab = Enum.find(tabs, &(&1.id == active))
    shell_id = shell_session_id(tab)
    if attached && attached.id != shell_id, do: Shell.detach(attached)

    cond do
      is_nil(shell_id) -> assign(socket, :attached, nil)
      attached && attached.id == shell_id -> socket
      true -> attach_shell(socket, tab)
    end
  end

  defp shell_session_id(%{kind: :shell, session: %{id: id}}), do: id
  defp shell_session_id(_tab), do: nil

  defp attach_shell(%{assigns: %{user: user, active: active}} = socket, %{target: target}) do
    case Shell.attach(user, target) do
      {:ok, session, scrollback} ->
        socket
        |> assign(:attached, session)
        |> push_event("shell-reset-#{target}", %{data: scrollback})

      :error ->
        socket |> assign(:attached, nil) |> close_tab(active, false)
    end
  end

  defp show_logs(%{assigns: %{tabs: tabs, active: active}} = socket) do
    case Enum.find(tabs, &(&1.id == active)) do
      %{kind: :logs} = tab ->
        lines = tab.buffer |> Enum.reverse() |> Enum.filter(&(&1.type in tab.types))

        socket
        |> stream(:lines, lines, reset: true, limit: -@log_cap)
        |> update_tab(tab.id, &%{&1 | empty: lines == []})

      _shell_or_none ->
        stream(socket, :lines, [], reset: true)
    end
  end

  defp close_tab(
         %{assigns: %{tabs: tabs, active: active, user: user}} = socket,
         id,
         end_session \\ true
       ) do
    case Enum.find(tabs, &(&1.id == id)) do
      nil ->
        socket

      tab ->
        stop(tab, user, end_session)
        rest = Enum.reject(tabs, &(&1.id == id))
        next = if active == id, do: rest |> List.last() |> then(&(&1 && &1.id)), else: active

        socket
        |> assign(:tabs, rest)
        |> assign(:attached, if(active == id, do: nil, else: socket.assigns.attached))
        |> activate(next)
    end
  end

  defp close_all(%{assigns: %{tabs: tabs, user: user}} = socket) do
    Enum.each(tabs, &stop(&1, user, true))

    socket
    |> assign(tabs: [], active: nil, attached: nil, asking_close: false)
    |> stream(:lines, [], reset: true)
  end

  defp stop(%{kind: :logs, snames: snames}, _user, _end_session) do
    for sname <- snames, type <- @types, do: Logs.unsubscribe_for_new_logs(sname, type)
  end

  defp stop(%{kind: :shell, target: target, session: session}, user, end_session) do
    Shell.detach(session)
    if end_session, do: Shell.close(user, target)
  end

  defp update_tab(socket, id, fun) do
    update(socket, :tabs, fn tabs -> Enum.map(tabs, &if(&1.id == id, do: fun.(&1), else: &1)) end)
  end

  # The logs of one instance, or of every instance of an app
  defp log_snames(target, app) when target == app do
    case Enum.filter(
           Enum.map(Deployer.Monitor.list(), &to_string/1),
           &String.starts_with?(&1, "#{app}-")
         ) do
      [] -> [target]
      snames -> snames
    end
  end

  defp log_snames(target, _app), do: [target]

  # A tab for every instance of an app shows the source of each line
  defp read_logs(snames, types, many) do
    # Only the streams the log server has for each instance
    for(
      sname <- snames,
      type <- Logs.get_types_by_sname(sname),
      (type = to_string(type)) in types,
      do: {sname, type}
    )
    |> Enum.flat_map(fn {sname, type} ->
      lines(
        sname,
        type,
        Logs.list_data_by_sname_log_type(sname, type, from: @log_minutes, order: :asc),
        many
      )
    end)
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.take(-@log_cap)
    |> Enum.reverse()
  end

  defp lines(sname, type, messages, many) do
    Enum.flat_map(messages, fn %{timestamp: timestamp, log: log} ->
      (log || "")
      |> String.split(["\n", "\r"], trim: true)
      |> Enum.map(fn text ->
        %{
          id: System.unique_integer([:positive, :monotonic]),
          timestamp: timestamp,
          at: DateTime.from_unix!(timestamp, :millisecond),
          source: sname,
          type: type,
          text: text,
          many: many
        }
      end)
    end)
  end

  defp language("deployex"), do: "deployex"

  defp language(name_or_sname) do
    case Catalog.node_info(name_or_sname) do
      %{language: language} when language in ["elixir", "erlang", "gleam"] ->
        language

      _ ->
        case Enum.find(Catalog.applications(), &(&1.name == name_or_sname)) do
          %{language: language} -> language
          _ -> "elixir"
        end
    end
  end

  defp logs_subtitle(%{whole_app: true, target: app}), do: "every instance of #{app}"
  defp logs_subtitle(%{target: target}), do: target

  defp logs_query(%{whole_app: false, target: target}), do: %{source: target}
  defp logs_query(_tab), do: %{}

  defp close_label(%{kind: :shell, label: label, target: target}),
    do: "End the #{label} session on #{target}"

  defp close_label(%{target: target}), do: "Close the logs of #{target}"

  defp shell_count(tabs) do
    case Enum.count(tabs, &(&1.kind == :shell)) do
      1 -> "1 shell session"
      count -> "#{count} shell sessions"
    end
  end

  defp message_color(%{type: "stderr"}), do: "var(--dx-error-text)"

  defp message_color(%{text: text}) do
    cond do
      String.contains?(text, "[error]") -> "var(--dx-error-text)"
      String.contains?(text, "[warning]") -> "var(--dx-warning-text)"
      true -> "var(--dx-base-content)"
    end
  end
end
