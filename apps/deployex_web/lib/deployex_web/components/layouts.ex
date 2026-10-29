defmodule DeployexWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use DeployexWeb, :controller` and
  `use DeployexWeb, :live_view`.
  """
  use DeployexWeb, :html

  alias DeployexWeb.HostInfo
  alias DeployexWeb.UI.Menu
  alias DeployexWeb.UI.Meter
  alias DeployexWeb.UI.Shell
  alias DeployexWeb.UI.ThemeSwitch

  embed_templates "layouts/*"

  @nav_items [
    %{path: "/applications", label: "Applications", icon: "hero-home"},
    %{path: "/logs/live", label: "Live Logs", icon: "hero-signal"},
    %{path: "/logs/history", label: "History Logs", icon: "hero-clock"},
    %{path: "/embedded-observer", label: "Observer Web", icon: "observer-web-logo"},
    %{path: "/terminal", label: "Host Terminal", icon: "hero-command-line"},
    %{path: "/hotupgrade", label: "Hot Upgrade", icon: "hero-arrow-up-circle"},
    %{path: "/documentation", label: "Documentation", icon: "hero-book-open"}
  ]

  @doc """
  Renders the app layout: the shell with the top bar and the sidebar around the page.

  ## Examples

      <Layouts.app flash={@flash} current_path={@current_path} current_user={@current_user} host_info={@host_info}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: "/"
  attr :current_user, :map, default: nil

  attr :host_info, :any,
    default: nil,
    doc: "the latest `Host.Info` reading, from `DeployexWeb.HostInfo`"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :nav_items, @nav_items)

    ~H"""
    <Shell.shell console="Agent Console" home={~p"/applications"}>
      <:top_bar_status>
        <div class="flex flex-wrap items-center gap-x-4.5 gap-y-1" role="group" aria-label="Host">
          <Meter.meter
            id="host-cpu"
            label="CPU"
            name="Host CPU"
            value={HostInfo.cpu_percent(@host_info)}
            detail={HostInfo.cores(@host_info)}
          />
          <Meter.meter
            id="host-memory"
            label="Memory"
            name="Host memory"
            value={HostInfo.memory_percent(@host_info)}
            detail={HostInfo.memory_total(@host_info)}
          />
        </div>
      </:top_bar_status>
      <:top_bar_end>
        <ThemeSwitch.theme_switch />
        <Menu.menu
          id="account-menu"
          label={"Account menu for #{display_name(@current_user)}"}
          button_class="inline-flex size-11 cursor-pointer items-center justify-center rounded-full"
        >
          <:button>
            <span class="flex size-9 items-center justify-center rounded-full bg-primary/20 text-[0.8125rem] font-bold text-primary-text">
              {initials(@current_user)}
            </span>
          </:button>
          <div class="mb-1.5 border-b border-base-300 px-2.5 pt-2 pb-2.5">
            <p class="truncate text-sm font-semibold">{display_name(@current_user)}</p>
          </div>
          <Menu.item
            id="theme-system"
            class="group"
            aria-pressed="false"
            phx-hook="ShellState"
            data-state="theme-system"
            data-state-attr="aria-pressed"
            phx-click={JS.dispatch("dx:toggle-system-theme")}
          >
            <.icon name="hero-computer-desktop" class="size-4" /> Match system theme
            <.icon name="hero-check" class="invisible ml-auto size-4 group-aria-pressed:visible" />
          </Menu.item>
          <Menu.item href={~p"/users/log_out"} method="delete">
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Log out
          </Menu.item>
        </Menu.menu>
      </:top_bar_end>
      <:sidebar>
        <Shell.nav_item
          :for={item <- @nav_items}
          navigate={item.path}
          label={item.label}
          active={active_route?(item.path, @current_path)}
        >
          <:icon><.nav_icon name={item.icon} /></:icon>
        </Shell.nav_item>
      </:sidebar>
      {render_slot(@inner_block)}
    </Shell.shell>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  # The built-in password user has a username. An OAuth user is a plain map
  # with an email. Show whichever identifies the logged-in user.
  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(%{email: email}) when is_binary(email), do: email
  defp display_name(_user), do: "Unknown"

  # Two letters for the account button: "sam.miller@example.com" gives "SM", "admin" gives "AD"
  defp initials(user) do
    user
    |> display_name()
    |> String.split("@")
    |> hd()
    |> String.split(~r/[._\-\s]+/, trim: true)
    |> case do
      [first, second | _] -> String.first(first) <> String.first(second)
      [single] -> String.slice(single, 0, 2)
      [] -> "?"
    end
    |> String.upcase()
  end

  # Only exact matches are active, so a parent route is not highlighted for its child routes
  defp active_route?(item_path, current_path) do
    String.trim_trailing(item_path, "/") == String.trim_trailing(current_path || "/", "/")
  end

  # The Observer Web item shows the Supervision Lens logo from the Observer Web
  # project (Observer.Web.Components.Icons), kept in sync manually.
  defp nav_icon(%{name: "observer-web-logo"} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      class="size-5"
    >
      <defs>
        <linearGradient id="dx-ow-logo-gradient" x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stop-color="#2563eb" />
          <stop offset="1" stop-color="#06b6d4" />
        </linearGradient>
      </defs>
      <circle cx="10.5" cy="10.5" r="7.5" /><line
        x1="16.2"
        y1="16.2"
        x2="21"
        y2="21"
        stroke-width="2.4"
      /><line x1="10.5" y1="8" x2="7.2" y2="13" /><line x1="10.5" y1="8" x2="13.8" y2="13" /><circle
        cx="10.5"
        cy="7.6"
        r="1.7"
        fill="url(#dx-ow-logo-gradient)"
        stroke="none"
      /><circle cx="7.0" cy="13.4" r="1.4" fill="currentColor" stroke="none" /><circle
        cx="14.0"
        cy="13.4"
        r="1.4"
        fill="currentColor"
        stroke="none"
      />
    </svg>
    """
  end

  defp nav_icon(assigns) do
    ~H"""
    <.icon name={@name} class="size-5" />
    """
  end
end
