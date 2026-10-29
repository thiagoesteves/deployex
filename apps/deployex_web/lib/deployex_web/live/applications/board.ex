defmodule DeployexWeb.ApplicationsLive.Board do
  @moduledoc """
  The Applications page: the page head, the This host card and the application table, built from
  `DeployexWeb.ApplicationsLive.View`.

  Logs and shell buttons open a tab in the dock through the `dx:dock-open` window event.
  """
  use DeployexWeb, :html

  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Tags

  @columns "minmax(200px,1.5fr) 176px 64px 92px 84px 168px 44px"

  attr :host_name, :string, required: true
  attr :attention, :integer, required: true

  def page_head(assigns) do
    ~H"""
    <header class="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
      <div>
        <h1 class="text-[26px] font-bold tracking-[-0.02em]">Applications</h1>
        <p class="dx-muted dx-mono mt-1.5 text-[13px]">{@host_name}</p>
      </div>
      <span :if={@attention > 0} class="dx-chip dx-s-ghost">
        <Icons.icon name="ghost" class="dx-gh" />
        {if @attention == 1, do: "1 app needs attention", else: "#{@attention} apps need attention"}
      </span>
    </header>
    """
  end

  attr :host, :map, required: true
  attr :pending_changes, :integer, required: true
  attr :asking, :boolean, required: true

  def host_card(assigns) do
    ~H"""
    <section class="dx-card" aria-label="This host">
      <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 px-[18px] py-3">
        <div class="flex flex-wrap items-center gap-x-6 gap-y-2">
          <span class="dx-stat items-center">
            <Tags.lang name={@host.icon} small label={@host.system} />{@host.system}
          </span>
          <span class="dx-stat"><span class="dx-lbl">Up</span><b>{@host.up}</b></span>
          <span class="dx-stat">
            <span class="dx-lbl">DeployEx</span><b>{@host.version}</b><span class="dx-muted">on OTP {@host.otp}</span>
          </span>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <button
            :if={@pending_changes > 0}
            id="host-config-review"
            type="button"
            class="dx-chip dx-s-start min-h-10 px-3.5"
            phx-click="show-config-changes"
          >
            {if @pending_changes == 1,
              do: "1 config change",
              else: "#{@pending_changes} config changes"} · Review
          </button>
          <button
            type="button"
            class="dx-btn"
            aria-label="Logs of DeployEx"
            phx-click={dock_open("logs", "deployex", "deployex")}
          >
            Logs
          </button>
          <button
            id="host-restart"
            type="button"
            class="dx-btn"
            phx-click="ask"
            phx-value-target="deployex"
          >
            Restart
          </button>
        </div>
      </div>
      <div :if={@asking} class="dx-ask" role="group" aria-label="Confirm the restart of DeployEx">
        <span class="flex-[1_1_320px]">
          <b>Restart DeployEx?</b>
          It stops every monitored application on this host, then starts again and deploys them.
        </span>
        <button
          id="host-restart-confirm"
          type="button"
          class="dx-btn dx-btn-danger"
          phx-click="restart-deployex"
        >
          Restart DeployEx
        </button>
        <button type="button" class="dx-btn" phx-click="cancel-ask">Cancel</button>
      </div>
    </section>
    """
  end

  attr :apps, :list, required: true
  attr :open, :any, required: true, doc: "the names of the expanded apps"
  attr :limits_open, :map, required: true, doc: "sname => true or false, set by the user"
  attr :ask, :any, required: true
  attr :sent, :any, required: true, doc: "the snames with a restart sent"

  attr :cleared, :map,
    required: true,
    doc: "name => version, for a ghosted version in its Undo window"

  def app_table(assigns) do
    assigns = assign(assigns, :columns, @columns)

    ~H"""
    <section class="dx-card overflow-hidden" aria-label="Applications on this host">
      <div class="overflow-x-auto">
        <div class="min-w-[1040px]">
          <div
            class="grid min-h-10 items-center gap-[18px] pr-5 pl-[26px]"
            style={"grid-template-columns: #{@columns}"}
          >
            <div class="dx-lbl">Application</div>
            <div class="dx-lbl">Status</div>
            <div class="dx-lbl text-right">CPU</div>
            <div class="dx-lbl text-right">Memory</div>
            <div class="dx-lbl text-right">Restarts</div>
            <div class="dx-lbl">Last deploy</div>
            <div></div>
          </div>
          <p :if={@apps == []} class="dx-muted border-t border-(--dx-base-300) px-[26px] py-6">
            No applications on this host. Add one under <code class="dx-mono">applications</code>
            in the DeployEx YAML.
          </p>
          <.app_row
            :for={app <- @apps}
            app={app}
            open={MapSet.member?(@open, app.name)}
            limits_open={@limits_open}
            ask={@ask}
            sent={@sent}
            cleared={@cleared[app.name]}
          />
        </div>
      </div>
    </section>
    """
  end

  attr :app, :map, required: true
  attr :open, :boolean, required: true
  attr :limits_open, :map, required: true
  attr :ask, :any, required: true
  attr :sent, :any, required: true
  attr :cleared, :any, required: true

  defp app_row(assigns) do
    ~H"""
    <div id={"app-#{@app.name}"}>
      <div class="dx-arow">
        <div class="flex min-w-0 items-center gap-3.5">
          <Tags.lang name={@app.language} label={@app.language_name} />
          <div class="min-w-0">
            <div class="text-lg font-bold tracking-[-0.01em]">{@app.name}</div>
            <div class="dx-muted dx-mono mt-0.5 text-[13px]">{@app.sub}</div>
          </div>
        </div>
        <div>
          <Tags.status text={@app.status.text} tone={@app.status.tone} />
          <span
            :if={@app.problems != []}
            class="dx-badge"
            style={"color: #{Tags.tone(:warning)}"}
            title={Enum.join(@app.problems, ", ")}
          >
            <Icons.icon name="warning" stroke="2" class="dx-ico size-[13px]" />{length(@app.problems)}
            <span class="sr-only">problems: {Enum.join(@app.problems, ", ")}</span>
          </span>
        </div>
        <div class="dx-num text-[15.5px] font-semibold">{@app.cpu}</div>
        <div class="dx-num text-[15.5px] font-semibold">{@app.memory}</div>
        <div
          class="dx-num text-[15.5px] font-semibold"
          style={"color: #{if @app.restarts > 0, do: Tags.tone(:warning), else: "inherit"}"}
          title={@app.restarts_title}
        >
          {@app.restarts}
        </div>
        <div class="flex items-center gap-2 text-sm">
          <Tags.deploy_tag :if={@app.deploy} type={@app.deploy.type} label={@app.deploy.label} />
          <span :if={@app.deploy} class="dx-muted">{@app.deploy.when}</span>
        </div>
        <button
          id={"app-#{@app.name}-toggle"}
          type="button"
          class="dx-ghost size-10"
          aria-expanded={to_string(@open)}
          aria-label={
            if @open,
              do: "Hide the instances of #{@app.name}",
              else: "Show the instances of #{@app.name}"
          }
          phx-click="toggle-app"
          phx-value-name={@app.name}
        >
          <Icons.icon
            name="chevron-down"
            stroke="2"
            class={[
              "dx-ico transition-transform motion-reduce:transition-none",
              @open && "rotate-180"
            ]}
          />
        </button>
      </div>

      <.alert :if={@app.alert || @cleared} app={@app} cleared={@cleared} />

      <div :if={@open} class="dx-inset">
        <div :if={@app.notes != []} class="flex flex-col gap-1 px-4 py-2.5 text-[12.5px]">
          <span
            :for={note <- @app.notes}
            class="font-semibold"
            style={"color: #{Tags.tone(note.tone)}"}
          >
            {note.text}
          </span>
        </div>
        <.instance_row
          :for={instance <- @app.instances}
          app={@app.name}
          instance={instance}
          limits_open={Map.get(@limits_open, instance.sname, instance.warnings != [])}
          asking={@ask == instance.sname}
          sent={MapSet.member?(@sent, instance.sname)}
        />
        <div
          :if={@ask == {:app, @app.name}}
          class="dx-ask"
          role="group"
          aria-label={"Confirm the restart of every instance of #{@app.name}"}
        >
          <span class="flex-[1_1_320px]">
            <b>Restart every instance of {@app.name}?</b>
            Each instance stops and starts again, one after the other, and its open connections drop.
          </span>
          <button
            id={"app-#{@app.name}-restart-all-confirm"}
            type="button"
            class="dx-btn dx-btn-danger"
            phx-click="restart-app"
            phx-value-name={@app.name}
          >
            Restart all
          </button>
          <button type="button" class="dx-btn" phx-click="cancel-ask">Cancel</button>
        </div>
        <div class="flex flex-wrap gap-2 border-t border-(--dx-base-300) px-4 py-2.5">
          <button
            type="button"
            class="dx-btn"
            aria-label={"Logs of every instance of #{@app.name}"}
            phx-click={dock_open("logs", @app.name, @app.name)}
          >
            Logs
          </button>
          <.link class="dx-btn" patch={~p"/applications/#{@app.name}/versions"}>Versions and mode</.link>
          <button
            id={"app-#{@app.name}-restart-all"}
            type="button"
            class="dx-btn"
            phx-click="ask"
            phx-value-target={"app:#{@app.name}"}
          >
            Restart all…
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :app, :map, required: true
  attr :cleared, :any, required: true

  defp alert(%{cleared: version} = assigns) when is_binary(version) do
    ~H"""
    <div class="dx-alert" role="status">
      <span class="inline-flex items-center gap-2 font-semibold" style={"color: #{Tags.tone(:muted)}"}>
        <Icons.icon name="ghost" class="dx-gh size-[17px]" />
        Cleared ghosted {@cleared}. This host can deploy it again.
      </span>
      <button
        id={"app-#{@app.name}-undo-clear"}
        type="button"
        class="dx-btn"
        phx-click="undo-clear"
        phx-value-name={@app.name}
      >
        Undo
      </button>
    </div>
    """
  end

  defp alert(assigns) do
    ~H"""
    <div class="dx-alert">
      <span
        class="inline-flex items-center gap-2 font-semibold"
        style={"color: #{Tags.tone(if @app.alert.kind == :ghosted, do: :error, else: :warning)}"}
      >
        <Icons.icon :if={@app.alert.kind == :ghosted} name="ghost" class="dx-gh size-[17px]" />
        <Icons.icon
          :if={@app.alert.kind != :ghosted}
          name="arrow-path"
          stroke="2"
          class="dx-ico size-4"
        />
        {@app.alert.text}
      </span>
      <button
        :if={@app.alert.kind == :ghosted}
        id={"app-#{@app.name}-clear-ghosted"}
        type="button"
        class="dx-btn dx-btn-er"
        phx-click="clear-ghosted"
        phx-value-name={@app.name}
        phx-value-version={@app.alert.version}
      >
        Clear ghosted {@app.alert.version}
      </button>
      <button
        type="button"
        class="dx-btn"
        aria-label={"Logs of #{@app.name}"}
        phx-click={dock_open("logs", @app.name, @app.name)}
      >
        View logs
      </button>
    </div>
    """
  end

  attr :app, :string, required: true
  attr :instance, :map, required: true
  attr :limits_open, :boolean, required: true
  attr :asking, :boolean, required: true
  attr :sent, :boolean, required: true

  defp instance_row(assigns) do
    ~H"""
    <div id={"instance-#{@instance.sname}"}>
      <div class="dx-irow">
        <div class="flex min-w-0 items-center gap-1">
          <button
            id={"instance-#{@instance.sname}-limits"}
            type="button"
            class="dx-iname"
            aria-expanded={to_string(@limits_open)}
            aria-label={"#{if @limits_open, do: "Hide", else: "Show"} the process, port and atom limits of #{@instance.sname}"}
            title={@instance.node}
            phx-click="toggle-limits"
            phx-value-sname={@instance.sname}
            phx-value-open={to_string(!@limits_open)}
          >
            <Icons.icon
              name="chevron-right"
              stroke="2.2"
              class={["dx-ico dx-muted size-[13px]", @limits_open && "rotate-90"]}
            />
            <span>{@instance.sname}</span>
          </button>
          <span
            :if={@instance.warnings != []}
            role="img"
            aria-label={Enum.join(@instance.warnings, ", ")}
            title={Enum.join(@instance.warnings, ", ")}
            class="inline-flex"
            style={"color: #{Tags.tone(:warning)}"}
          >
            <Icons.icon name="warning" stroke="2" class="dx-ico size-[13px]" />
          </span>
        </div>
        <Tags.status
          text={Enum.join(Enum.reject([@instance.status.text, @instance.version], &is_nil/1), " ")}
          tone={@instance.status.tone}
          class="font-medium"
        />
        <div class="dx-num text-[12.5px]">{@instance.cpu}</div>
        <div class="dx-num text-[12.5px]">{@instance.memory}</div>
        <div
          class="dx-num text-[12.5px]"
          style={"color: #{if @instance.restarts > 0, do: Tags.tone(:warning), else: Tags.tone(:muted)}"}
          title={@instance.restarts_title}
        >
          {if @instance.restarts == 1, do: "1 restart", else: "#{@instance.restarts} restarts"}
        </div>
        <div class="flex items-center gap-1.5">
          <Tags.deploy_tag type={if @instance.deploy == :hot_upgrade, do: :hot, else: :full} />
          <span :if={@instance.up} class="dx-mono dx-muted text-xs">up {@instance.up}</span>
        </div>
        <div class="flex justify-end gap-1.5">
          <button
            type="button"
            class="dx-iact"
            aria-label={"Logs of #{@instance.sname}"}
            phx-click={dock_open("logs", @instance.sname, @app)}
          >
            <Icons.icon name="lines" class={nil} /><span>Logs</span>
          </button>
          <button
            type="button"
            class="dx-iact"
            aria-label={"#{@instance.shell} on #{@instance.sname}, opens in the dock"}
            phx-click={dock_open("shell", @instance.sname, @app)}
          >
            <Icons.icon name="command-line" class={nil} /><span>{@instance.shell}</span>
          </button>
          <button
            id={"instance-#{@instance.sname}-restart"}
            type="button"
            class="dx-iact dx-iact-er"
            aria-label={"Restart #{@instance.sname}…"}
            phx-click="ask"
            phx-value-target={@instance.sname}
          >
            <Icons.icon name="arrow-path" class={nil} /><span>{if @sent,
              do: "Restart sent",
              else: "Restart…"}</span>
          </button>
        </div>
      </div>
      <div
        :if={@asking}
        class="dx-ask"
        role="group"
        aria-label={"Confirm the restart of #{@instance.sname}"}
      >
        <span class="flex-[1_1_320px]">
          <b>Restart {@instance.sname}?</b>
          The node stops and starts again, and its open connections drop.
        </span>
        <button
          id={"instance-#{@instance.sname}-restart-confirm"}
          type="button"
          class="dx-btn dx-btn-danger"
          phx-click="restart-instance"
          phx-value-sname={@instance.sname}
        >
          Restart instance
        </button>
        <button type="button" class="dx-btn" phx-click="cancel-ask">Cancel</button>
      </div>
      <div
        :if={@limits_open}
        class="dx-limits"
        role="group"
        aria-label={"Limits of #{@instance.sname}"}
      >
        <p :if={@instance.limits == []} class="dx-muted col-span-3 text-[12.5px]">
          No reading yet. DeployEx reads the limits of a running instance every 5 seconds.
        </p>
        <div :for={limit <- @instance.limits} class="dx-lim">
          <div class="flex items-baseline justify-between gap-2">
            <span class="dx-lbl">{limit.name}</span>
            <span
              class="dx-mono text-[12.5px] font-semibold"
              style={"color: #{level_text(limit.level)}"}
            >
              {limit.percent_text}
            </span>
          </div>
          <span
            class="dx-lbar"
            role="meter"
            aria-label={"#{limit.name} at #{limit.percent} percent of the limit"}
            aria-valuemin="0"
            aria-valuemax="100"
            aria-valuenow={limit.percent}
          >
            <i style={"width: #{max(limit.percent, 1.5)}%; background: #{level_fill(limit.level)}"}></i>
          </span>
          <div class="flex justify-between gap-2 text-[11.5px]">
            <span class="dx-mono dx-muted">{limit.count} of {limit.limit}</span>
            <span
              :if={limit.trend}
              class="font-semibold whitespace-nowrap"
              style={"color: #{Tags.tone(:warning)}"}
            >
              {limit.trend}
            </span>
          </div>
        </div>
        <.link
          class="dx-btn"
          navigate={~p"/embedded-observer"}
          aria-label={"Open #{@instance.sname} in Observer Web"}
        >
          Observer Web
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  The window event that opens a dock tab, or focuses it when it is open.
  """
  def dock_open(kind, target, app) do
    JS.dispatch("dx:dock-open", detail: %{kind: kind, target: target, app: app})
  end

  defp level_fill(2), do: "var(--dx-error)"
  defp level_fill(1), do: "var(--dx-warning)"
  defp level_fill(_level), do: "var(--dx-info)"

  defp level_text(2), do: "var(--dx-error-text)"
  defp level_text(1), do: "var(--dx-warning-text)"
  defp level_text(_level), do: "var(--dx-muted)"
end
