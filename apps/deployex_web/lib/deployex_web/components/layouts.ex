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
  alias DeployexWeb.UI.Bell
  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Menu
  alias DeployexWeb.UI.Meter
  alias DeployexWeb.UI.Shell
  alias DeployexWeb.UI.ThemeSwitch

  embed_templates "layouts/*"

  @nav_items [
    %{path: "/applications", label: "Applications", icon: "home"},
    %{path: "/logs/live", label: "Live Logs", icon: "signal"},
    %{path: "/logs/history", label: "History Logs", icon: "clock"},
    %{path: "/embedded-observer", label: "Observer Web", icon: "observer-web"},
    %{path: "/terminal", label: "Terminal", icon: "command-line"},
    %{path: "/hotupgrade", label: "Hot Upgrade", icon: "arrow-up-circle"},
    %{path: "/documentation", label: "Documentation", icon: "book-open"}
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

  attr :recent_events, :list,
    default: [],
    doc: "the bell items, from `DeployexWeb.RecentEvents`"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :nav_items, @nav_items)

    ~H"""
    <Shell.shell console="Agent Console" home={~p"/applications"}>
      <:top_bar_center>
        <.live_component module={DeployexWeb.Components.Search} id="search" />
      </:top_bar_center>
      <:top_bar_status>
        <div class="dx-meters" role="group" aria-label="Host">
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
        <Bell.bell items={@recent_events} all_href="/logs/live" all_text="View logs" />
        <ThemeSwitch.theme_switch />
        <Menu.menu
          id="account-menu"
          label={"Account menu for #{display_name(@current_user)}"}
          button_class="dx-avatar"
        >
          <:button>{initials(@current_user)}</:button>
          <div class="mb-1.5 border-b border-(--dx-base-300) px-2.5 pt-2 pb-2.5">
            <div class="truncate text-[13.5px] font-semibold">{display_name(@current_user)}</div>
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
            <Icons.icon name="computer-desktop" class="dx-ico size-4" /> Match system theme
            <Icons.icon
              name="check"
              stroke="2"
              class="dx-ico invisible ml-auto size-4 group-aria-pressed:visible"
            />
          </Menu.item>
          <Menu.item href={~p"/users/log_out"} method="delete">
            <Icons.icon name="logout" class="dx-ico size-4" /> Log out
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
          <:icon><Icons.icon name={item.icon} stroke="1.6" /></:icon>
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
end
