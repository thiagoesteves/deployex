defmodule DeployexWeb.UI.Menu do
  @moduledoc """
  A button that opens a panel of links and actions, like the account menu.

  Opening moves the focus into the panel. Escape closes it and moves the focus back to the button, through
  the `Menu` hook in `app.js`. A click outside closes it.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the accessible name of the button"
  attr :button_class, :any, default: nil
  attr :panel_class, :any, default: nil
  attr :panel_role, :string, default: nil
  attr :panel_label, :string, default: nil
  slot :button, required: true, doc: "the button content"
  slot :inner_block, required: true, doc: "the panel content, usually `item/1` entries"

  def menu(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative"
      phx-hook="Menu"
      phx-click-away={close(@id)}
      data-escape={close(@id) |> JS.focus(to: "##{@id}-button")}
    >
      <button
        id={"#{@id}-button"}
        type="button"
        class={@button_class}
        aria-label={@label}
        aria-expanded="false"
        aria-controls={"#{@id}-panel"}
        phx-click={toggle(@id)}
      >
        {render_slot(@button)}
      </button>
      <div
        id={"#{@id}-panel"}
        class={["dx-menu hidden", @panel_class]}
        role={@panel_role}
        aria-label={@panel_label}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  A full-width row in a menu panel. Pass `href` or `navigate` for a link, nothing for a button.
  """
  attr :rest, :global, include: ~w(href navigate method download)
  slot :inner_block, required: true

  def item(%{rest: rest} = assigns) when is_map_key(rest, :href) or is_map_key(rest, :navigate) do
    ~H"""
    <.link class={item_class()} {@rest}>{render_slot(@inner_block)}</.link>
    """
  end

  def item(assigns) do
    ~H"""
    <button type="button" class={item_class()} {@rest}>{render_slot(@inner_block)}</button>
    """
  end

  defp item_class, do: "dx-menu-item"

  defp toggle(id) do
    JS.toggle(to: "##{id}-panel")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-button")
    |> JS.focus_first(to: "##{id}-panel")
  end

  defp close(id) do
    JS.hide(to: "##{id}-panel")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-button")
  end
end
