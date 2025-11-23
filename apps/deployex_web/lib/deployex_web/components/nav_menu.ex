defmodule DeployexWeb.Components.NavMenu do
  @moduledoc """
  Modern navigation menu component with enhanced UX features.

  Features:
  - Responsive design with mobile support
  - Smooth animations and transitions
  - Active route highlighting
  - Keyboard navigation support
  - Accessibility improvements
  - Modern DaisyUI styling
  """
  use DeployexWeb, :live_component

  alias DeployexWeb.Cache.UiSettings
  import DeployexWeb.Layouts, only: [theme_toggle: 1]

  # Navigation menu items configuration
  @nav_items [
    %{
      id: "applications",
      path: "/applications",
      label: "Applications",
      icon: "hero-home",
      color: "primary",
      description: "Manage your applications"
    },
    %{
      id: "live-logs",
      path: "/logs/live",
      label: "Live Logs",
      icon: "hero-signal",
      color: "secondary",
      description: "View real-time logs"
    },
    %{
      id: "history-logs",
      path: "/logs/history",
      label: "History Logs",
      icon: "hero-clock",
      color: "accent",
      description: "Browse historical logs"
    },
    %{
      id: "observer",
      path: "/embedded-observer",
      label: "Observer Web",
      icon: "hero-chart-bar",
      color: "info",
      description: "System monitoring"
    },
    %{
      id: "terminal",
      path: "/terminal",
      label: "Host Terminal",
      icon: "hero-command-line",
      color: "warning",
      description: "Access terminal"
    },
    %{
      id: "docs",
      path: "/applications/deployex/docs",
      label: "Documentation",
      icon: "hero-book-open",
      color: "success",
      description: "View documentation"
    }
  ]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, nav_items: @nav_items)

    ~H"""
    <div id={"#{@id}"} class="drawer-side shadow-sm">
      <label for="nav-drawer" class="drawer-overlay lg:hidden"></label>
      <!-- Modern Flat Sidebar -->
      <aside
        class={
        "min-h-screen bg-base-100 transition-all duration-200 ease-out " <>
        "flex flex-col"
      }
        style={nav_bar_width(@ui_settings.nav_menu_collapsed)}
      >
        <!-- Brand Section -->
        <div class="p-6 border-b border-base-300">
          <.modern_brand collapsed={@ui_settings.nav_menu_collapsed} />
        </div>
        <!-- Navigation -->
        <nav class="flex-1 p-3" role="navigation">
          <div class="space-y-1">
            <%= for item <- @nav_items do %>
              <.flat_nav_item
                item={item}
                collapsed={@ui_settings.nav_menu_collapsed}
                active={active_route?(item.path, @current_path || "/")}
              />
            <% end %>
          </div>
        </nav>
        <!-- User Profile -->
        <div class="p-4 border-t border-base-300">
          <.user_profile collapsed={@ui_settings.nav_menu_collapsed} />
        </div>
        <!-- Toggle Button as Menu Item -->
        <div class="px-3 pb-4">
          <.toggle_menu_item collapsed={@ui_settings.nav_menu_collapsed} target={@myself} />
        </div>
      </aside>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event(
        "collapse-click",
        %{"collapsed" => "true"},
        %{assigns: %{ui_settings: ui_settings}} = socket
      ) do
    updated_options = %{ui_settings | nav_menu_collapsed: false}
    UiSettings.set(updated_options)
    {:noreply, assign(socket, :ui_settings, updated_options)}
  end

  def handle_event(
        "collapse-click",
        %{"collapsed" => "false"},
        %{assigns: %{ui_settings: ui_settings}} = socket
      ) do
    updated_options = %{ui_settings | nav_menu_collapsed: true}
    UiSettings.set(updated_options)
    {:noreply, assign(socket, :ui_settings, updated_options)}
  end

  # Modern Brand Component - Ultra Flat Design with Perfect Centering
  defp modern_brand(assigns) do
    ~H"""
    <div class={
      "flex items-center " <>
      if(@collapsed, do: "gap-4", else: "justify-center")
    }>
      <!-- Minimal Logo -->
      <div class="flex-shrink-0">
        <div class="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
          <.icon name="hero-cube" class="w-6 h-6 text-primary" />
        </div>
      </div>
      <!-- Brand Text - Only show when expanded -->
      <div :if={@collapsed} class="min-w-0 flex-1">
        <h1 class="text-xl font-bold text-base-content tracking-tight">
          DeployEx
        </h1>
        <p class="text-sm text-base-content/60 font-medium">
          Management Console
        </p>
      </div>
    </div>
    """
  end

  # Ultra Flat Navigation Item - Modern Design with Perfect Centering
  defp flat_nav_item(assigns) do
    ~H"""
    <a
      href={@item.path}
      class={
        "flex items-center rounded-lg transition-all duration-150 group " <>
        if(@active,
          do: "bg-primary text-primary-content shadow-sm",
          else: "hover:bg-base-200/70 text-base-content/80 hover:text-base-content"
        ) <>
        if(@collapsed, do: " gap-3 px-3 py-2.5", else: " justify-center px-3 py-3")
      }
      title={@item.description}
      aria-label={@item.label}
    >
      <!-- Icon -->
      <div class="flex-shrink-0">
        <.icon
          name={@item.icon}
          class={
            "w-5 h-5 transition-colors duration-150 " <>
            if(@active,
              do: "text-primary-content",
              else: "text-base-content/60 group-hover:text-base-content"
            )
          }
        />
      </div>
      <!-- Label - Only show when expanded -->
      <div :if={@collapsed} class="flex-1 min-w-0">
        <span class={
          "text-sm font-medium truncate " <>
          if(@active,
            do: "text-primary-content",
            else: "text-base-content/80 group-hover:text-base-content"
          )
        }>
          {@item.label}
        </span>
      </div>
      <!-- Badge for notifications - Only show when expanded -->
      <div :if={@item.id == "live-logs" and @collapsed} class="flex-shrink-0">
        <div class="w-2 h-2 bg-error rounded-full"></div>
      </div>
    </a>
    """
  end

  # Toggle Button as Menu Item with Perfect Centering
  defp toggle_menu_item(assigns) do
    assigns =
      assigns
      |> assign(
        icon: if(assigns.collapsed, do: "hero-chevron-left", else: "hero-chevron-right"),
        label: if(assigns.collapsed, do: "Collapse", else: "Expand")
      )

    ~H"""
    <button
      id="toggle-nav-menu-button"
      phx-click="collapse-click"
      phx-value-collapsed={to_string(@collapsed)}
      phx-target={@target}
      class={
        "flex items-center rounded-lg transition-all duration-150 group " <>
        "hover:bg-base-200/70 text-base-content/80 hover:text-base-content w-full " <>
        if(@collapsed, do: "gap-3 px-3 py-2.5", else: "justify-center px-3 py-3")
      }
      title={@label <> " menu"}
    >
      <!-- Icon -->
      <div class="flex-shrink-0">
        <.icon
          name={@icon}
          class="w-5 h-5 transition-colors duration-150 text-base-content/60 group-hover:text-base-content"
        />
      </div>
      <!-- Label - Only show when expanded -->
      <div :if={@collapsed} class="flex-1 min-w-0 text-left">
        <span class="text-sm font-medium truncate text-base-content/80 group-hover:text-base-content">
          {@label}
        </span>
      </div>
    </button>
    """
  end

  # Modern User Profile Component
  defp user_profile(assigns) do
    ~H"""
    <div class={
      "flex items-center " <>
      if(@collapsed, do: "gap-3", else: "justify-center")
    }>
      <!-- Avatar -->
      <div class="flex-shrink-0">
        <div class="w-8 h-8 bg-success/10 rounded-lg flex items-center justify-center">
          <.icon name="hero-user" class="w-4 h-4 text-success" />
        </div>
      </div>
      <!-- User Info -->
      <div :if={@collapsed} class="flex-1 min-w-0">
        <p class="text-sm font-medium text-base-content truncate">Admin</p>
        <p class="text-xs text-base-content/60">Online</p>
      </div>
      <!-- Settings Menu -->
      <div :if={@collapsed} class="dropdown dropdown-top dropdown-end">
        <div tabindex="0" role="button" class="btn btn-ghost btn-xs">
          <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
        </div>
        <ul
          tabindex="0"
          class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow-lg border border-base-200"
        >
          <li><a class="text-sm"><.icon name="hero-cog-6-tooth" class="w-4 h-4" />Settings</a></li>
          <li>
            <a class="text-sm"><.icon name="hero-question-mark-circle" class="w-4 h-4" />Help</a>
          </li>
          <div class="divider my-1"></div>
          <li class="menu-title text-xs">Theme</li>
          <li>
            <div class="flex justify-between items-center p-2">
              <.theme_toggle />
            </div>
          </li>
          <div class="divider my-1"></div>
          <li>
            <a class="text-sm">
              <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4" />Logout
            </a>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # Utility Functions
  defp nav_bar_width(collapsed) do
    if collapsed do
      "width: 16rem;"
    else
      "width: 5rem;"
    end
  end

  defp active_route?(item_path, current_path) do
    # Normalize paths by removing trailing slashes
    normalized_item_path = String.trim_trailing(item_path, "/")
    normalized_current_path = String.trim_trailing(current_path || "/", "/")

    # Only exact matches are considered active
    # This prevents parent routes from being highlighted when child routes are active
    normalized_item_path == normalized_current_path
  end
end
