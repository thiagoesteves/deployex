defmodule DeployexWeb.UI.Search do
  @moduledoc """
  The top bar search, as a combobox: the filter tags set, then the field. With focus and no text it shows
  the hint chips, then the results in groups. The `Search` hook in `app.js` moves through the results
  with the arrow keys, opens one with Enter, clears the field with Escape, and removes the last tag with
  Backspace in an empty field.
  """
  use Phoenix.Component

  alias DeployexWeb.UI.Icons
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :query, :string, required: true
  attr :placeholder, :string, required: true
  attr :label, :string, required: true

  attr :target, :any,
    required: true,
    doc: "the component that handles the `search` and `focus` events"

  attr :hints, :list, default: [], doc: "texts offered as chips while the field is empty"

  attr :groups, :list,
    default: [],
    doc: "`%{title: ..., items: [%{label: ..., context: ..., href: ..., patch: ...}]}`"

  attr :tags, :list,
    default: [],
    doc:
      "the filters set, shown in the field: `%{label: ..., href: ..., patch: ...}`, href removes it"

  def combobox(assigns) do
    assigns = assign(assigns, :searching, String.trim(assigns.query) != "")

    ~H"""
    <div id={@id} class="dx-search" role="search" phx-hook="Search" data-query={@query}>
      <div class="dx-s-field">
        <Icons.icon name="search" class="dx-ico dx-s-ico" />
        <ul :if={@tags != []} class="dx-s-tags" aria-label="Filters">
          <li :for={tag <- @tags} class="dx-s-tag">
            {tag.label}
            <.link
              class="dx-s-untag"
              navigate={if(!tag.patch, do: tag.href)}
              patch={if(tag.patch, do: tag.href)}
              aria-label={"Remove the filter #{tag.label}"}
              data-tag-remove
            >
              <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-3.5" />
            </.link>
          </li>
        </ul>
        <form
          id={"#{@id}-form"}
          class="dx-s-form"
          phx-change="search"
          phx-submit="search"
          phx-target={@target}
        >
          <input
            id={"#{@id}-input"}
            type="search"
            name="q"
            value={@query}
            placeholder={@placeholder}
            aria-label={@label}
            role="combobox"
            aria-expanded="false"
            aria-controls={"#{@id}-list"}
            aria-autocomplete="list"
            autocomplete="off"
            phx-debounce="120"
            phx-focus={JS.push("focus", target: @target)}
          />
        </form>
        <button
          :if={@searching}
          type="button"
          class="dx-tb-btn dx-s-clear"
          aria-label="Clear the search"
          phx-click={
            JS.push("search", value: %{q: ""}, target: @target) |> JS.focus(to: "##{@id}-input")
          }
        >
          <Icons.icon name="x-mark" stroke="2" class="dx-ico size-4" />
        </button>
      </div>
      <div id={"#{@id}-list"} class="dx-drop" role="listbox" aria-label="Search results">
        <%= if @searching do %>
          <div :for={group <- @groups} role="group" aria-label={group.title}>
            <div class="dx-drop-h" aria-hidden="true">{group.title}</div>
            <.link
              :for={{item, index} <- Enum.with_index(group.items)}
              id={"#{@id}-#{slug(group.title)}-#{index}"}
              class="dx-hit"
              role="option"
              navigate={if(!item.patch, do: item.href)}
              patch={if(item.patch, do: item.href)}
            >
              <b>{item.label}</b><span>{item.context}</span>
            </.link>
          </div>
          <p :if={@groups == []} class="dx-muted p-2.5 text-[0.8125rem]">No match for {@query}.</p>
        <% else %>
          <div :if={@hints != []} class="dx-drop-h">Try</div>
          <div :if={@hints != []} class="flex flex-wrap gap-1.5 px-2.5 pt-1 pb-2">
            <button
              :for={hint <- @hints}
              type="button"
              class="dx-ctx"
              phx-click={
                JS.push("search", value: %{q: hint}, target: @target) |> JS.focus(to: "##{@id}-input")
              }
            >
              {hint}
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp slug(title), do: title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
