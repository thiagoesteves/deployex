defmodule DeployexWeb.Components.Attention do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :message, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :inner_form, doc: "the slot for adding form to input data"
  slot :inner_button, doc: "the slot for adding form to input data"

  def content(assigns) do
    ~H"""
    <div class="flex items-center justify-between bg-gray-200 w-full">
      <div
        id={"live-#{@id}-alert"}
        class={["p-2 bg-gray-300 border-l-8 rounded-l-lg", @class]}
        role="alert"
      >
        <div class="flex items-center">
          <div class="flex items-center py-8 ">
            <svg
              class="flex-shrink-0 w-4 h-4 me-2"
              aria-hidden="true"
              xmlns="http://www.w3.org/2000/svg"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5ZM9.5 4a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM12 15H8a1 1 0 0 1 0-2h1v-3H8a1 1 0 0 1 0-2h2a1 1 0 0 1 1 1v4h1a1 1 0 0 1 0 2Z" />
            </svg>
            <span class="sr-only">Info</span>
            <h3 class="text-sm  font-bold">{@title}</h3>
          </div>
          <div class="ml-2 mr-2 mt-2 mb-2 text-xs">
            {@message}
          </div>
          {render_slot(@inner_form)}
        </div>
      </div>
      {render_slot(@inner_button)}
    </div>
    """
  end
end
