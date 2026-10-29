defmodule DeployexWeb.UI.Shell do
  @moduledoc """
  The page frame: a top bar over a sidebar and the page content.

  Below the `lg` breakpoint the sidebar is a drawer. From `lg` up it stays open, and the top bar toggle
  collapses it to an icon rail. `root.html.heex` keeps the collapsed state on `<html data-sidebar>`, so it
  survives live navigation.
  """
  use Phoenix.Component

  alias DeployexWeb.UI.Icons
  alias Phoenix.LiveView.JS

  attr :console, :string,
    required: true,
    doc: "the console name under the logo, like Agent Console"

  attr :home, :string, required: true, doc: "the page the logo links to"
  slot :top_bar_start, doc: "after the logo, for a back link"
  slot :top_bar_center, doc: "the middle of the top bar, for search"
  slot :top_bar_status, doc: "before the end, for the host meters. A row of its own on a phone"

  slot :top_bar_end,
    doc: "the right of the top bar, for notifications, the theme switch and the account menu"

  slot :sidebar, required: true, doc: "the navigation, as `nav_item/1` entries"
  slot :dock, doc: "a panel fixed to the bottom of the page"
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div class="dx-app flex min-h-dvh flex-col">
      <header id="shell-top-bar" class="dx-topbar sticky top-0">
        <div class="dx-tb-left">
          <button
            type="button"
            class="dx-tb-btn lg:hidden"
            aria-label="Open the menu"
            aria-controls="shell-sidebar"
            phx-click={JS.dispatch("click", to: "#shell-drawer")}
          >
            <Icons.icon name="bars" class="dx-ico" />
          </button>
          <button
            id="shell-sidebar-toggle"
            type="button"
            class="dx-tb-btn max-lg:hidden"
            aria-label="Menu"
            title="Collapse or expand the menu"
            aria-controls="shell-sidebar"
            aria-expanded="true"
            phx-hook="ShellState"
            data-state="sidebar-expanded"
            data-state-attr="aria-expanded"
            phx-click={JS.dispatch("dx:toggle-sidebar")}
          >
            <Icons.icon name="bars" class="dx-ico" />
          </button>
          <.link navigate={@home} class="dx-brand min-h-11">
            <span class="dx-brand-mark"><img src="/images/logo.svg" alt="" width="30" height="30" /></span>
            <span><b>DeployEx</b><small>{@console}</small></span>
          </.link>
          {render_slot(@top_bar_start)}
        </div>
        <div :if={@top_bar_center != []} class="dx-tb-mid">{render_slot(@top_bar_center)}</div>
        <div class="dx-tb-right">
          <div :if={@top_bar_status != []} class="max-md:order-last max-md:basis-full">
            {render_slot(@top_bar_status)}
          </div>
          {render_slot(@top_bar_end)}
        </div>
      </header>

      <div class="drawer flex-1 lg:drawer-open">
        <%!-- Ignored, so a re-render of the page does not close the open drawer --%>
        <input
          id="shell-drawer"
          type="checkbox"
          class="drawer-toggle"
          aria-hidden="true"
          tabindex="-1"
          phx-update="ignore"
        />
        <div class="drawer-content flex min-w-0 flex-col">
          <main id="shell-main" class="min-w-0 flex-1">
            {render_slot(@inner_block)}
          </main>
          {render_slot(@dock)}
        </div>
        <div class="drawer-side z-[70] lg:top-14 lg:z-30 lg:h-[calc(100dvh-3.5rem)]">
          <label for="shell-drawer" class="drawer-overlay" aria-label="Close the menu"></label>
          <aside id="shell-sidebar" class="dx-side min-h-full" aria-label="Agent navigation">
            <nav aria-label="DeployEx" class="flex flex-col gap-0.5 p-2.5">
              {render_slot(@sidebar)}
            </nav>
          </aside>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  A sidebar link. It uses live navigation, so a page change keeps the shell and does not reload.
  """
  attr :navigate, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  slot :icon, required: true

  def nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      title={@label}
      aria-current={@active && "page"}
      class={["dx-nav", @active && "dx-nav-on"]}
    >
      {render_slot(@icon)}
      <span>{@label}</span>
    </.link>
    """
  end
end
