defmodule DeployexWeb.UI.Shell do
  @moduledoc """
  The page frame: a top bar over a sidebar and the page content.

  Below the `lg` breakpoint the sidebar is a drawer. From `lg` up it stays open, and the top bar toggle
  collapses it to an icon rail. `root.html.heex` keeps the collapsed state on `<html data-sidebar>`, so it
  survives live navigation.
  """
  use Phoenix.Component

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
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div class="flex min-h-dvh flex-col bg-base-200 text-base-content">
      <header
        id="shell-top-bar"
        class="sticky top-0 z-40 flex min-h-(--dx-topbar-height) flex-wrap items-center gap-x-4 gap-y-2 border-b border-base-300 bg-base-100 px-3.5 py-2 text-(length:--dx-text-base)"
      >
        <div class="flex items-center gap-2.5">
          <button
            type="button"
            class="inline-flex size-11 items-center justify-center rounded-lg text-muted hover:bg-base-200 hover:text-base-content lg:hidden"
            aria-label="Open the menu"
            aria-controls="shell-sidebar"
            phx-click={JS.dispatch("click", to: "#shell-drawer")}
          >
            <span class="hero-bars-3 size-5" aria-hidden="true" />
          </button>
          <button
            id="shell-sidebar-toggle"
            type="button"
            class="hidden size-11 items-center justify-center rounded-lg text-muted hover:bg-base-200 hover:text-base-content lg:inline-flex"
            aria-label="Menu"
            title="Collapse or expand the menu"
            aria-controls="shell-sidebar"
            aria-expanded="true"
            phx-hook="ShellState"
            data-state="sidebar-expanded"
            data-state-attr="aria-expanded"
            phx-click={JS.dispatch("dx:toggle-sidebar")}
          >
            <span class="hero-bars-3 size-5" aria-hidden="true" />
          </button>
          <.link
            navigate={@home}
            class="inline-flex min-h-11 items-center gap-2.5 rounded-lg pr-2 text-base-content"
          >
            <img src="/images/logo.svg" alt="" class="size-8" />
            <span class="leading-tight">
              <span class="block text-[0.9375rem] font-bold tracking-tight">DeployEx</span>
              <span class="block text-xs font-medium text-muted">{@console}</span>
            </span>
          </.link>
          {render_slot(@top_bar_start)}
        </div>
        <div class="min-w-0 flex-1">{render_slot(@top_bar_center)}</div>
        <div :if={@top_bar_status != []} class="max-md:order-last max-md:basis-full">
          {render_slot(@top_bar_status)}
        </div>
        <div class="flex items-center gap-x-3">
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
          <main id="shell-main" class="flex-1">
            {render_slot(@inner_block)}
          </main>
        </div>
        <div class="drawer-side z-50 lg:top-(--dx-topbar-height) lg:z-30 lg:h-[calc(100dvh-var(--dx-topbar-height))]">
          <label for="shell-drawer" class="drawer-overlay" aria-label="Close the menu"></label>
          <aside
            id="shell-sidebar"
            class="flex min-h-full w-(--dx-sidebar-width) flex-col border-r border-base-300 bg-base-100 lg:sidebar-collapsed:w-(--dx-rail-width)"
          >
            <nav aria-label="Main" class="flex flex-col gap-0.5 p-2.5">
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
      class={[
        "flex min-h-11 items-center gap-3 rounded-lg px-3 text-sm font-medium",
        "lg:sidebar-collapsed:justify-center lg:sidebar-collapsed:px-0",
        if(@active,
          do: "bg-nav-active text-primary-content",
          else: "text-base-content/80 hover:bg-base-200 hover:text-base-content"
        )
      ]}
    >
      <span class="flex size-5 shrink-0 items-center justify-center" aria-hidden="true">
        {render_slot(@icon)}
      </span>
      <span class="truncate lg:sidebar-collapsed:sr-only">{@label}</span>
    </.link>
    """
  end
end
