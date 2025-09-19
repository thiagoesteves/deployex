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

  embed_templates "layouts/*"

  @doc """
  Renders the app layout

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layout.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :ui_settings, :map, required: true
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="nav-drawer" type="checkbox" class="drawer-toggle" />
      
    <!-- Mobile Menu Button -->
      <div class="navbar lg:hidden bg-base-100 border-b border-base-200">
        <div class="navbar-start">
          <label for="nav-drawer" class="btn btn-square btn-ghost hover:bg-base-200">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 6h16M4 12h16M4 18h16"
              >
              </path>
            </svg>
          </label>
        </div>
        <div class="navbar-center">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
              <img src="/images/logo.svg" alt="DeployEx" class="w-5 h-5" />
            </div>
            <span class="text-lg font-semibold text-base-content">DeployEx</span>
          </div>
        </div>
        <div class="navbar-end">
          <.theme_toggle />
        </div>
      </div>
      
    <!-- Main Content -->
      <div class="drawer-content flex flex-col min-h-screen">
        <main class="flex-1">
          {render_slot(@inner_block)}
        </main>
      </div>
      
    <!-- Navigation Sidebar -->
      <.live_component
        module={DeployexWeb.Components.NavMenu}
        ui_settings={@ui_settings}
        current_path={Map.get(assigns, :current_path, "/")}
        id="navbar"
      />
    </div>

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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "system"})}
        title="System Theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "light"})}
        title="Light Theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "dark"})}
        title="Dark Theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
