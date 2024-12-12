defmodule DeployexWeb.Components.MultiSelect do
  @moduledoc """
  Multi select box

  References:
   * https://www.creative-tim.com/twcomponents/component/multi-select

  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :selected_text, :string, required: true
  attr :selected, :list, required: true
  attr :unselected, :list, required: true
  attr :show_options, :boolean, required: true

  def content(assigns) do
    ~H"""
    <div class="w-full m flex flex-col items-center mx-auto">
      <div class="w-full px-2">
        <div class="flex flex-col items-center relative">
          <div class="w-full  ">
            <div class="my-2 p-1 flex border border-gray-300 bg-white rounded ">
              <div class="flex flex-auto flex-wrap">
                <div class="flex text-ms font-normal items-center p-2 py-1 bg-gray-200  rounded border-gray-200 ">
                  {@selected_text}
                </div>

                <%= for item <- @selected do %>
                  <%= for key <- item.keys do %>
                    <div class={[
                      "flex justify-center items-center m-1 font-medium py-1 px-2 bg-white rounded-full border",
                      border_item_color(item.name)
                    ]}>
                      <div class={[
                        "text-xs font-normal leading-none max-w-full flex-initial",
                        text_item_color(item.name)
                      ]}>
                        {"#{item.name}:#{key}"}
                      </div>
                      <button
                        id={String.replace("#{@id}-#{item.name}-#{key}-remove-item", "@", "-")}
                        class="flex flex-auto flex-row-reverse"
                        phx-click="multi-select-remove-item"
                        phx-value-key={key}
                        phx-value-item={item.name}
                      >
                        <div>
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            width="100%"
                            height="100%"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke="currentColor"
                            stroke-width="2"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            class="feather feather-x cursor-pointer hover:text-teal-400 rounded-full w-4 h-4 ml-2"
                          >
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                          </svg>
                        </div>
                      </button>
                    </div>
                  <% end %>
                <% end %>
                <div class="flex-1">
                  <input
                    placeholder=""
                    phx-click="toggle-options"
                    class="bg-transparent p-1 px-2 appearance-none outline-none h-full w-full text-gray-800"
                  />
                </div>
              </div>
              <div class="text-gray-300 w-8 py-1 pl-2 pr-1 border-l flex items-center border-gray-200 ">
                <button
                  id={"#{@id}-toggle-options"}
                  class="cursor-pointer w-6 h-6 text-gray-600 outline-none focus:outline-none"
                  phx-click="toggle-options"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="100%"
                    height="100%"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    class="feather feather-chevron-up w-4 h-4"
                  >
                    <polyline :if={!@show_options} points="18 15 12 9 6 15"></polyline>
                    <polyline :if={@show_options} points="6 9 12 15 18 9"></polyline>
                  </svg>
                </button>
              </div>
            </div>

            <div
              :if={@show_options}
              class="relative shadow top-100 bg-white z-40 lef-0 rounded max-h-select"
            >
              <div phx-mounted={
                JS.transition(
                  {"first:ease-in duration-300", "first:opacity-0 first:p-0 first:h-0",
                   "first:opacity-100"},
                  time: 300
                )
              }>
                <%= for item <- @unselected do %>
                  <div class="w-full flex-wrap">
                    <div class="flex items-start p-2">
                      <div class="text-xs font-bold text-black">{item.name}:</div>
                    </div>

                    <div class="flex flex-wrap">
                      <%= for key <- item.keys do %>
                        <button
                          id={String.replace("#{@id}-#{item.name}-#{key}-add-item", "@", "-")}
                          class="flex justify-center items-center m-1 font-medium px-2 rounded-full text-gray-700 bg-gray-100 border border-gray-300"
                          phx-click="multi-select-add-item"
                          phx-value-key={key}
                          phx-value-item={item.name}
                        >
                          <div class="text-xs font-normal leading-none max-w-full flex-initial">
                            {key}
                          </div>
                          <div class="flex flex-auto flex-row-reverse">
                            <div>
                              <svg
                                xmlns="http://www.w3.org/2000/svg"
                                width="100%"
                                height="100%"
                                fill="none"
                                viewBox="0 0 24 24"
                                stroke="currentColor"
                                stroke-width="2"
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                class="feather feather-x cursor-pointer hover:text-teal-400 rounded-full w-4 h-4 ml-2"
                              >
                                <polyline points="20 6 9 17 4 12"></polyline>
                              </svg>
                            </div>
                          </div>
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def border_item_color("services"), do: "border-teal-300"
  def border_item_color("logs"), do: "border-yellow-400"
  def border_item_color("apps"), do: "border-blue-400"
  # coveralls-ignore-start
  def border_item_color(_), do: "border-gray-300"
  # coveralls-ignore-stop

  def text_item_color("services"), do: "text-teal-700"
  def text_item_color("logs"), do: "text-yellow-700"
  def text_item_color("apps"), do: "text-blue-700"
  # coveralls-ignore-start
  def text_item_color(_), do: "text-teal-700"
  # coveralls-ignore-stop
end
