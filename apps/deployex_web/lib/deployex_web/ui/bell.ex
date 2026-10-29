defmodule DeployexWeb.UI.Bell do
  @moduledoc """
  The notifications bell: a badge with the unread count, and a panel with the recent items.

  The read state is per browser. The `Bell` hook in `app.js` keeps the last read item in `localStorage`,
  sets the badge and bolds the unread items, and shows each time in the browser's time zone.
  """
  use Phoenix.Component

  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Menu

  @tones %{
    ghost: "var(--dx-error-text)",
    error: "var(--dx-error)",
    warning: "var(--dx-warning)",
    info: "var(--dx-info)"
  }

  attr :id, :string, default: "bell"

  attr :items, :list,
    required: true,
    doc:
      "maps with `id`, `at`, `tone` (:ghost, :error, :warning or :info), `title`, `detail` and `href`, newest first"

  attr :all_href, :string, required: true, doc: "the footer link"
  attr :all_text, :string, required: true

  def bell(assigns) do
    assigns = assign(assigns, :tones, @tones)

    ~H"""
    <div id={"#{@id}-state"} phx-hook="Bell" data-bell={@id}>
      <Menu.menu
        id={@id}
        label="Notifications"
        button_class="dx-tb-btn relative"
        panel_class="dx-notif"
        panel_role="dialog"
        panel_label="Notifications"
      >
        <:button>
          <Icons.icon name="bell" />
          <span class="dx-nbadge hidden" aria-hidden="true" data-bell-badge></span>
        </:button>
        <div class="mb-1 flex items-center justify-between gap-2 border-b border-(--dx-base-300) px-2 pt-1.5 pb-2">
          <b class="text-sm">Notifications</b>
          <button type="button" class="dx-nlink hidden" data-bell-mark-read>Mark all as read</button>
        </div>
        <p :if={@items == []} class="dx-muted px-2.5 py-3 text-[13px]">No events yet.</p>
        <.link :for={item <- @items} class="dx-nitem" navigate={item.href} data-bell-item={item.id}>
          <Icons.icon
            :if={item.tone == :ghost}
            name="ghost"
            class="dx-gh mt-0.5 size-[15px]"
            style={"color: #{@tones.ghost}"}
          />
          <span :if={item.tone != :ghost} class="dx-dot mt-1.5" style={"color: #{@tones[item.tone]}"}></span>
          <span class="min-w-0 flex-1">
            <span class="dx-nt" data-bell-title>{item.title}</span>
            <span class="dx-nd">{item.detail}</span>
          </span>
          <time
            class="dx-mono dx-muted whitespace-nowrap text-[11.5px]"
            datetime={DateTime.to_iso8601(item.at)}
          >
            {Calendar.strftime(item.at, "%H:%M")}
          </time>
        </.link>
        <.link
          class="dx-menu-item mt-1 justify-center rounded-t-none border-t border-(--dx-base-300)"
          navigate={@all_href}
        >
          {@all_text}
        </.link>
      </Menu.menu>
    </div>
    """
  end
end
