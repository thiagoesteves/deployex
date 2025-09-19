defmodule DeployexWeb.Components.CopyToClipboard do
  @moduledoc false
  use DeployexWeb, :html
  use Phoenix.Component

  attr :id, :string, required: true
  attr :message, :string, required: true

  def content(assigns) do
    ~H"""
    <button
      class="text-gray-500"
      phx-click={JS.dispatch("phx:copy_to_clipboard", detail: %{text: @message, id: @id})}
    >
      <div class="flex gap-1 items-center object-center">
        <div id={"c2c-default-message-#{@id}"}>
          <div class="flex items-center gap-0.5">
            <svg
              class="w-4 h-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
              >
              </path>
            </svg>
          </div>
        </div>
        <div id={"c2c-success-message-#{@id}"} hidden>
          <div class="flex items-center gap-0.5">
            <svg
              class="w-4 h-4 text-green-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7">
              </path>
            </svg>
          </div>
        </div>
      </div>
    </button>
    """
  end
end
