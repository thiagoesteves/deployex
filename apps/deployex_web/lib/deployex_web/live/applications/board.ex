defmodule DeployexWeb.ApplicationsLive.Board do
  @moduledoc """
  The Applications page: the page head, the This host card and the application table, built from
  `DeployexWeb.ApplicationsLive.View`.

  Logs and shell buttons open a tab in the dock through the `dx:dock-open` window event.
  """
  use DeployexWeb, :html

  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Tags

  @columns "minmax(200px,1.5fr) 176px 56px 84px 68px 140px 117px"

  attr :host_name, :string, required: true

  attr :attention, :map,
    required: true,
    doc: "the count of apps that need attention, and if one is blocked"

  attr :only_attention, :boolean, required: true, doc: "whether the list shows only those apps"

  def page_head(assigns) do
    ~H"""
    <header class="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
      <div>
        <h1 class="text-[1.625rem] font-bold tracking-[-0.02em]">Applications</h1>
        <p class="dx-muted dx-mono mt-1.5 text-[0.8125rem]">{@host_name}</p>
      </div>
      <button
        :if={@attention.count > 0}
        id="apps-attention"
        type="button"
        class={["dx-chip dx-chip-btn", if(@attention.blocking, do: "dx-s-ghost", else: "dx-s-start")]}
        aria-pressed={to_string(@only_attention)}
        phx-click="toggle-attention"
      >
        <Icons.icon :if={@only_attention} name="check" stroke="2.4" class="dx-ico size-3.5" />
        <Icons.icon :if={not @only_attention} name="warning" stroke="2" class="dx-ico size-3.5" />
        {if @attention.count == 1,
          do: "1 app needs attention",
          else: "#{@attention.count} apps need attention"}
      </button>
    </header>
    """
  end

  @doc """
  The head of a page about one app: a link back to Applications, the language icon, the name and a line.
  """
  attr :name, :string, required: true
  attr :language, :string, required: true
  attr :logo, :string, default: nil, doc: "the app's own logo, shown instead of the language icon"
  attr :subtitle, :string, required: true
  slot :inner_block, doc: "on the right of the head, like a count chip"

  def app_head(assigns) do
    ~H"""
    <div class="flex flex-col gap-2.5">
      <.link class="dx-back" navigate={~p"/applications"}>
        <Icons.icon name="arrow-left" stroke="2" class="dx-ico size-[15px]" />Applications
      </.link>
      <header class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
        <div class="flex items-center gap-3.5">
          <Tags.lang name={@language} label={String.capitalize(@language)} logo={@logo} />
          <div>
            <h1 class="text-[1.625rem] font-bold tracking-[-0.02em]">{@name}</h1>
            <p class="dx-muted dx-mono mt-1 text-[0.8125rem]">{@subtitle}</p>
          </div>
        </div>
        {render_slot(@inner_block)}
      </header>
    </div>
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

  attr :limits_open, :map,
    required: true,
    doc: "sname => true when its limits are open, closed by default"

  attr :ask, :any, required: true
  attr :sent, :any, required: true, doc: "the snames with a restart sent"
  attr :hidden, :integer, default: 0, doc: "the apps a filter hides"
  attr :hidden_text, :string, default: nil, doc: "what the filter shows, above Show all"

  attr :cleared, :map,
    required: true,
    doc: "name => version, for a ghosted version in its Undo window"

  def app_table(assigns) do
    assigns = assign(assigns, :columns, @columns)

    ~H"""
    <section class="dx-card overflow-hidden" aria-label="Applications on this host">
      <div class="overflow-x-auto">
        <div class="min-w-[984px]">
          <div
            class="grid min-h-10 items-center gap-4 pr-5 pl-[26px]"
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
          <div :if={@apps == []} class="dx-empty" id="apps-empty">
            <Icons.icon name="cube" class="dx-ico dx-muted size-7" />
            <b class="text-[0.9375rem]">No applications on this host</b>
            <p class="dx-muted max-w-[460px] text-[0.84375rem]">
              Add one under <code class="dx-mono">applications</code>
              in deployex.yaml. DeployEx deploys it when its release bucket has a version.
            </p>
            <div class="flex flex-wrap items-center justify-center gap-2">
              <span class="dx-muted text-[0.8125rem]">How to build and add an app:</span>
              <.link
                :for={
                  {label, page} <- [
                    {"Elixir", "guide-local-elixir"},
                    {"Erlang", "guide-local-erlang"},
                    {"Gleam", "guide-local-gleam"}
                  ]
                }
                class="dx-btn"
                navigate={~p"/documentation?#{%{page: "#{page}.html"}}"}
              >
                {label}
              </.link>
              <.link class="dx-btn" navigate={~p"/documentation?#{%{page: "guide-yaml.html"}}"}>YAML reference</.link>
            </div>
          </div>
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
      <div
        :if={@hidden > 0}
        class="dx-muted flex flex-wrap items-center justify-between gap-2.5 border-t border-(--dx-base-300) px-5 py-3 text-[0.8125rem]"
      >
        <span>{@hidden_text}</span>
        <button id="apps-show-all" type="button" class="dx-btn" phx-click="show-all">
          Show all
        </button>
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
          <Tags.lang name={@app.language} label={@app.language_name} logo={@app.logo} />
          <div class="min-w-0">
            <div class="text-lg font-bold tracking-[-0.01em]">{@app.name}</div>
            <div class="dx-muted dx-mono mt-0.5 text-[0.8125rem]">{@app.sub}</div>
          </div>
        </div>
        <div class="flex items-center">
          <Tags.status text={@app.status.text} tone={@app.status.tone} />
          <span
            :if={@app.problems != []}
            id={"app-#{@app.name}-problems-tip"}
            class="dx-badge"
            phx-hook="Tip"
          >
            <button
              id={"app-#{@app.name}-problems"}
              type="button"
              style={"color: #{Tags.tone(:warning)}"}
              aria-label={"#{problems(@app.problems)}: #{Enum.join(@app.problems, ", ")}. Show the instances"}
              phx-click="toggle-app"
              phx-value-name={@app.name}
              phx-value-open="true"
            >
              <Icons.icon name="warning" stroke="2" class="dx-ico size-4" />{length(@app.problems)}
            </button>
            <span popover="manual" class="dx-tip" aria-hidden="true">
              <span :for={problem <- @app.problems} class="block">{problem}</span>
            </span>
          </span>
        </div>
        <div class="dx-num text-[0.96875rem] font-semibold">{@app.cpu}</div>
        <div class="dx-num text-[0.96875rem] font-semibold">{@app.memory}</div>
        <.restarts
          id={"app-#{@app.name}-restarts"}
          restarts={@app.restarts}
          class="text-[0.96875rem] font-semibold"
          color="inherit"
        />
        <div class="flex items-center gap-2 text-sm">
          <Tags.deploy_tag :if={@app.deploy} type={@app.deploy.type} label={@app.deploy.label} />
          <span :if={@app.deploy} class="dx-muted">{@app.deploy.when}</span>
        </div>
        <button
          id={"app-#{@app.name}-toggle"}
          type="button"
          class="dx-ghost size-10 justify-self-end"
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
        <div :if={@app.notes != []} class="flex flex-col gap-1 px-4 py-2.5 text-[0.78125rem]">
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
          limits_open={Map.get(@limits_open, instance.sname, false)}
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
          <.link class="dx-btn" navigate={~p"/applications/#{@app.name}/versions"}>Versions and mode</.link>
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
    <div class="dx-callout dx-callout-muted" role="status">
      <Icons.icon name="ghost" class="dx-gh dx-callout-ico" />
      <div class="dx-callout-text">
        <b>Cleared ghosted {@cleared}</b>
        <span>This host can deploy it again.</span>
      </div>
      <div class="dx-callout-acts">
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
    </div>
    """
  end

  defp alert(assigns) do
    ~H"""
    <div class={"dx-callout dx-callout-#{@app.alert.tone}"}>
      <Icons.icon :if={@app.alert.kind == :ghosted} name="ghost" class="dx-gh dx-callout-ico" />
      <Icons.icon
        :if={@app.alert.kind != :ghosted}
        name="arrow-path"
        stroke="2"
        class="dx-ico dx-callout-ico"
      />
      <div class="dx-callout-text">
        <b>{@app.alert.title}</b>
        <span>{@app.alert.detail}</span>
      </div>
      <div class="dx-callout-acts">
        <button
          :if={@app.alert.kind == :ghosted}
          id={"app-#{@app.name}-clear-ghosted"}
          type="button"
          class="dx-btn"
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
            aria-label={"#{if @limits_open, do: "Hide", else: "Show"} the details and limits of #{@instance.sname}"}
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
            id={"instance-#{@instance.sname}-warnings"}
            class="inline-flex"
            phx-hook="Tip"
          >
            <span
              role="img"
              aria-label={Enum.join(@instance.warnings, ", ")}
              class="inline-flex"
              style={"color: #{Tags.tone(:warning)}"}
            >
              <Icons.icon name="warning" stroke="2" class="dx-ico size-4" />
            </span>
            <span popover="manual" class="dx-tip" aria-hidden="true">
              <span :for={warning <- @instance.warnings} class="block">{warning}</span>
            </span>
          </span>
        </div>
        <Tags.status
          text={Enum.join(Enum.reject([@instance.status.text, @instance.version], &is_nil/1), " ")}
          tone={@instance.status.tone}
          class="font-medium"
        />
        <div class="dx-num text-[0.78125rem]">{@instance.cpu}</div>
        <div class="dx-num text-[0.78125rem]">{@instance.memory}</div>
        <.restarts
          id={"instance-#{@instance.sname}-restarts"}
          restarts={@instance.restarts}
          class="text-[0.78125rem]"
          color={Tags.tone(:muted)}
        />
        <div class="flex items-center gap-1.5">
          <Tags.deploy_tag type={if @instance.deploy == :hot_upgrade, do: :hot, else: :full} />
          <span :if={@instance.up} class="dx-mono dx-muted text-xs">up {@instance.up}</span>
        </div>
        <div class="flex justify-end gap-1">
          <.icon_action
            id={"instance-#{@instance.sname}-logs"}
            icon="lines"
            tip="Logs"
            label={"Logs of #{@instance.sname}"}
            phx-click={dock_open("logs", @instance.sname, @app)}
          />
          <.icon_action
            id={"instance-#{@instance.sname}-shell"}
            icon="command-line"
            tip={@instance.shell}
            label={"#{@instance.shell} on #{@instance.sname}, opens in the dock"}
            phx-click={dock_open("shell", @instance.sname, @app)}
          />
          <.icon_action
            id={"instance-#{@instance.sname}-restart"}
            icon={if @sent, do: "check", else: "arrow-path"}
            tip={if @sent, do: "Restart sent", else: "Restart…"}
            label={
              if @sent, do: "Restart sent to #{@instance.sname}", else: "Restart #{@instance.sname}…"
            }
            danger
            phx-click="ask"
            phx-value-target={@instance.sname}
          />
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
        aria-label={"Details and limits of #{@instance.sname}"}
      >
        <dl class="dx-idetail">
          <div :if={@instance.node} class="dx-ditem">
            <dt class="dx-lbl">Node</dt>
            <dd class="dx-mono">
              {@instance.node}<.copy_button
                id={"instance-#{@instance.sname}-copy-node"}
                text={@instance.node}
                label="node name"
              />
            </dd>
          </div>
          <div :for={port <- @instance.ports} class="dx-ditem">
            <dt class="dx-lbl">{port.key}</dt>
            <dd class="dx-mono">{port.base}</dd>
          </div>
          <div :for={{url, index} <- Enum.with_index(@instance.urls)} class="dx-ditem">
            <dt class="dx-lbl">URL</dt>
            <dd>
              <a class="dx-link dx-mono" href={url} target="_blank" rel="noopener noreferrer">
                {url}<Icons.icon name="external" class="dx-ico ml-1 inline size-3.5" /><span class="sr-only"> (opens in a new tab)</span>
              </a><.copy_button
                id={"instance-#{@instance.sname}-copy-url-#{index}"}
                text={url}
                label="URL"
              />
            </dd>
          </div>
        </dl>
        <p :if={@instance.limits == []} class="dx-muted col-span-3 text-[0.78125rem]">
          No reading yet. DeployEx reads the limits of a running instance every 5 seconds.
        </p>
        <div :for={limit <- @instance.limits} class="dx-lim">
          <div class="flex items-baseline justify-between gap-2">
            <span class="dx-lbl">{limit.name}</span>
            <span
              class="dx-mono text-[0.78125rem] font-semibold"
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
            <b :if={limit.restart_at} class="dx-lmark" style={"left: #{limit.restart_at}%"}></b>
          </span>
          <div class="flex flex-wrap justify-between gap-x-2 text-xs">
            <span class="dx-mono dx-muted whitespace-nowrap">{limit.count} of {limit.limit}</span>
            <span :if={limit.watch} class="dx-muted whitespace-nowrap">{limit.watch}</span>
          </div>
          <span
            :if={limit.trend}
            class="text-xs font-semibold whitespace-nowrap"
            style={"color: #{Tags.tone(:warning)}"}
          >
            {limit.trend}
          </span>
        </div>
        <span
          id={"instance-#{@instance.sname}-observer-tip"}
          class="flex self-stretch"
          phx-hook="Tip"
        >
          <.link
            id={"instance-#{@instance.sname}-observer"}
            class="dx-ltile"
            navigate={~p"/embedded-observer"}
            aria-label={"Open #{@instance.sname} in Observer Web"}
          >
            <Icons.icon name="observer-web" class="size-6" gradient={"dx-ow-#{@instance.sname}"} />
          </.link>
          <span popover="manual" class="dx-tip" aria-hidden="true">Observer Web</span>
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :tip, :string, required: true, doc: "the short name in the tooltip"
  attr :label, :string, required: true, doc: "the accessible name"
  attr :danger, :boolean, default: false
  attr :rest, :global

  # An icon button of an instance row, named by a tooltip on hover and keyboard focus
  defp icon_action(assigns) do
    ~H"""
    <span id={"#{@id}-tip"} class="inline-flex" phx-hook="Tip">
      <button
        id={@id}
        type="button"
        class={["dx-iact dx-iact-icon", @danger && "dx-iact-er"]}
        aria-label={@label}
        {@rest}
      >
        <Icons.icon name={@icon} class={nil} />
      </button>
      <span popover="manual" class="dx-tip" aria-hidden="true">{@tip}</span>
    </span>
    """
  end

  attr :id, :string, required: true

  attr :restarts, :map,
    required: true,
    doc: "the count, whether a crash is among them, and the tooltip lines"

  attr :class, :string, default: nil
  attr :color, :string, required: true, doc: "the color with no crash"

  # The restart count, amber for crashes, with the crash and the other restarts apart in a tooltip
  defp restarts(assigns) do
    ~H"""
    <div
      id={@id}
      class={["dx-num", @class]}
      style={"color: #{if @restarts.crash, do: Tags.tone(:warning), else: @color}"}
      phx-hook="Tip"
    >
      {@restarts.count}<span class="sr-only">: {Enum.join(@restarts.lines, ", ")}</span>
      <span popover="manual" class="dx-tip" aria-hidden="true">
        <span :for={line <- @restarts.lines} class="block">{line}</span>
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :label, :string, required: true, doc: "what it copies, like node name"

  # A small button that copies text, named by its tooltip, which says Copied after a click
  defp copy_button(assigns) do
    ~H"""
    <span id={"#{@id}-tip"} class="inline-flex align-middle" phx-hook="Tip">
      <button
        id={@id}
        type="button"
        class="dx-copy"
        data-copy={@text}
        aria-label={"Copy the #{@label}"}
        phx-click={JS.dispatch("dx:copy")}
      >
        <Icons.icon name="copy" class="size-3.5" />
      </button>
      <span popover="manual" class="dx-tip" aria-hidden="true" data-text={"Copy the #{@label}"}>
        Copy the {@label}
      </span>
      <span class="sr-only" aria-live="polite"></span>
    </span>
    """
  end

  defp problems([_problem]), do: "1 problem"
  defp problems(problems), do: "#{length(problems)} problems"

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
