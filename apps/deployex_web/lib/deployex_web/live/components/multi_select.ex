defmodule DeployexWeb.Components.MultiSelect do
  @moduledoc """
  Multi select box

  References:
   * https://www.creative-tim.com/twcomponents/component/multi-select

  """
  use Phoenix.Component

  alias DeployexWeb.Helper
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :selected_text, :string, required: true
  attr :selected, :list, required: true
  attr :unselected, :list, required: true
  attr :show_options, :boolean, required: true

  def content(assigns) do
    ~H"""
    <div class="w-full">
      <!-- Selected Items Display -->
      <div class="flex flex-wrap gap-2 mb-4">
        <div class="badge badge-neutral badge-lg">{@selected_text}</div>

        <%= for item <- @selected do %>
          <%= for key <- item.keys do %>
            <div class={["badge badge-lg gap-2", badge_color(item.name)]}>
              <span class="text-xs font-medium">{"#{item.name}:#{key}"}</span>
              <button
                id={Helper.normalize_id("#{@id}-#{item.name}-#{key}-remove-item")}
                class="btn btn-ghost btn-xs btn-circle"
                phx-click="multi-select-remove-item"
                phx-value-key={key}
                phx-value-item={item.name}
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  >
                  </path>
                </svg>
              </button>
            </div>
          <% end %>
        <% end %>
      </div>
      
    <!-- Toggle Button -->
      <div class="flex justify-center mb-4">
        <button
          id={Helper.normalize_id("#{@id}-toggle-options")}
          class="btn btn-outline btn-sm"
          phx-click="toggle-options"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              :if={!@show_options}
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19 9l-7 7-7-7"
            >
            </path>
            <path
              :if={@show_options}
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M5 15l7-7 7 7"
            >
            </path>
          </svg>
          {if @show_options, do: "Hide Options", else: "Show Options"}
        </button>
      </div>
      
    <!-- Available Options -->
      <div :if={@show_options} class="collapse collapse-open bg-base-200 rounded-lg">
        <div
          class="collapse-content p-4"
          phx-mounted={
            JS.transition(
              {"first:ease-in duration-300", "first:opacity-0 first:scale-95",
               "first:opacity-100 first:scale-100"},
              time: 300
            )
          }
        >
          <%= for item <- @unselected do %>
            <div class="mb-6 last:mb-0">
              <h3 class="text-sm font-semibold text-base-content mb-3 flex items-center gap-2">
                <div class={["w-3 h-3 rounded-full", category_color(item.name)]}></div>
                {String.capitalize(item.name)}
              </h3>

              <div class="flex flex-wrap gap-2">
                <%= for key <- item.keys do %>
                  <button
                    id={Helper.normalize_id("#{@id}-#{item.name}-#{key}-add-item")}
                    class={[
                      "btn btn-sm gap-2",
                      if(key in item.unselected_highlight, do: "btn-success", else: "btn-neutral")
                    ]}
                    phx-click="multi-select-add-item"
                    phx-value-key={key}
                    phx-value-item={item.name}
                  >
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                      >
                      </path>
                    </svg>
                    {key}
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp badge_color("services"), do: "badge-primary"
  defp badge_color("logs"), do: "badge-neutral"

  defp category_color("services"), do: "bg-primary"
  defp category_color("logs"), do: "bg-neutral"
end
