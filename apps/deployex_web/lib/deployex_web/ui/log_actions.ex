defmodule DeployexWeb.UI.LogActions do
  @moduledoc """
  Copy and Export for a list of log lines, on the Logs page and in a dock logs tab.

  Copy puts the lines shown on the clipboard, through `dx:copy-lines` in `app.js`, and its label says how
  many it copied. Export downloads every stored line that matches, as `.log` text or `.jsonl`.
  """
  use Phoenix.Component
  use DeployexWeb, :verified_routes

  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Menu
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true, doc: "the prefix of the element ids"
  attr :rows, :string, required: true, doc: "the id of the element that holds the shown rows"
  attr :empty, :boolean, required: true, doc: "whether no line shows, which turns Copy off"

  attr :export, :map,
    required: true,
    doc: "the export params, from `DeployexWeb.LogsExport.params/1`"

  def actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <button
        id={"#{@id}-copy"}
        type="button"
        class="dx-btn"
        title="Copy the lines shown"
        disabled={@empty}
        phx-click={JS.dispatch("dx:copy-lines", detail: %{from: "##{@rows}"})}
      >
        <Icons.icon name="copy" class="dx-ico size-3.5" />
        <span id={"#{@id}-copy-label"} phx-update="ignore" data-label="Copy">Copy</span>
      </button>
      <Menu.menu
        id={"#{@id}-export"}
        label="Export the lines"
        button_class="dx-btn"
        panel_class="dx-menu-below w-[280px]"
      >
        <:button>
          <Icons.icon name="arrow-down-tray" class="dx-ico size-3.5" /> Export
          <Icons.icon name="chevron-down" stroke="2" class="dx-ico size-3" />
        </:button>
        <Menu.item
          id={"#{@id}-export-log"}
          href={~p"/logs/export?#{@export ++ [format: "log"]}"}
          download
        >
          Plain text <span class="dx-muted dx-mono ml-auto text-xs">.log</span>
        </Menu.item>
        <Menu.item
          id={"#{@id}-export-jsonl"}
          href={~p"/logs/export?#{@export ++ [format: "jsonl"]}"}
          download
        >
          JSON lines <span class="dx-muted dx-mono ml-auto text-xs">.jsonl</span>
        </Menu.item>
        <p class="dx-muted px-2.5 pt-1.5 pb-1 text-xs">
          All the matching lines the log server keeps, not only the lines shown.
        </p>
      </Menu.menu>
    </div>
    """
  end
end
