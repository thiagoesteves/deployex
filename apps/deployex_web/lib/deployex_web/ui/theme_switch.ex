defmodule DeployexWeb.UI.ThemeSwitch do
  @moduledoc """
  The light and dark switch. It starts from the system setting, and a click sets the other theme.

  `root.html.heex` holds the theme on `<html data-theme>` and handles the `dx:toggle-theme` event. The
  `ShellState` hook in `app.js` keeps `aria-checked` in step with it.
  """
  use Phoenix.Component

  import DeployexWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, default: "theme-switch"

  def theme_switch(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="switch"
      aria-checked="false"
      aria-label="Dark mode"
      title="Dark mode"
      class="inline-flex min-h-11 items-center justify-center rounded-lg px-1"
      phx-hook="ShellState"
      data-state="theme-dark"
      data-state-attr="aria-checked"
      phx-click={JS.dispatch("dx:toggle-theme")}
    >
      <span
        class="relative block h-7.5 w-14 rounded-full border border-base-300 bg-base-300 transition-colors motion-reduce:transition-none dark:bg-info/40"
        aria-hidden="true"
      >
        <span class="absolute top-0.5 left-0.5 flex size-6 items-center justify-center rounded-full bg-base-100 shadow transition-transform motion-reduce:transition-none dark:translate-x-6.5">
          <.icon name="hero-sun-micro" class="size-3.5 text-warning-text dark:hidden" />
          <.icon name="hero-moon-micro" class="hidden size-3.5 text-info-text dark:block" />
        </span>
      </span>
    </button>
    """
  end
end
