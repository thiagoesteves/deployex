defmodule DeployexWeb.UI.ThemeSwitch do
  @moduledoc """
  The light and dark switch. It starts from the system setting, and a click sets the other theme.

  `root.html.heex` holds the theme on `<html data-theme>` and handles the `dx:toggle-theme` event. The
  `ShellState` hook in `app.js` keeps `aria-checked` in step with it.
  """
  use Phoenix.Component

  alias DeployexWeb.UI.Icons
  alias Phoenix.LiveView.JS

  attr :id, :string, default: "theme-switch"

  def theme_switch(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="dx-switch"
      role="switch"
      aria-checked="false"
      aria-label="Dark mode"
      title="Switch between light and dark mode"
      phx-hook="ShellState"
      data-state="theme-dark"
      data-state-attr="aria-checked"
      phx-click={JS.dispatch("dx:toggle-theme")}
    >
      <span class="dx-sw-knob" aria-hidden="true">
        <Icons.icon name="sun" stroke="2" class="dx-ico size-3.5 text-warning-text dark:hidden" />
        <Icons.icon name="moon" stroke="2" class="dx-ico hidden size-3.5 text-info-text dark:block" />
      </span>
    </button>
    """
  end
end
