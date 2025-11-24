defmodule DeployexWeb.Components.Progress do
  @moduledoc false
  use Phoenix.Component
  alias DeployexWeb.Helper

  attr :id, :string, required: true
  slot :header, required: true
  slot :footer, required: true
  slot :inner_block, required: true

  def content(assigns) do
    ~H"""
    <div id={@id} class="modal modal-open">
      <div class="modal-backdrop bg-black/40 backdrop-blur-md" aria-hidden="true"></div>
      <div class="modal-box max-w-lg bg-base-100 shadow-2xl border-0 rounded-xl p-0 overflow-hidden">
        <!-- Header Section -->
        <div class="bg-gradient-to-r from-base-200/50 to-base-300/30 px-8 py-6 border-b border-base-200/50">
          <div class="flex items-start justify-between">
            <div class="flex items-center gap-4">
              <div class="w-14 h-14 rounded-xl bg-warning/10 flex items-center justify-center ring-2 ring-warning/20">
                <svg
                  class="w-7 h-7 text-warning"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2.5"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                  >
                  </path>
                </svg>
              </div>
              <div>
                <h3 class="text-2xl font-bold text-base-content leading-tight">
                  {render_slot(@header)}
                </h3>
              </div>
            </div>
          </div>
        </div>
        <!-- Content Section -->
        <div class="px-8 py-6">
          <div class="text-base-content/90 text-lg leading-relaxed">
            {render_slot(@inner_block)}
          </div>
        </div>
        <!-- Footer Section -->
        <div class="px-8 py-6 bg-base-50/30 border-t border-base-200/50">
          <div class="flex gap-4 justify-end">
            {render_slot(@footer)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :event, :string, required: true
  slot :inner_block, required: true

  def done_button(assigns) do
    ~H"""
    <button
      id={Helper.normalize_id("done-button-#{@id}")}
      class="btn btn-lg bg-gradient-to-r from-primary to-primary-focus hover:from-primary-focus hover:to-primary text-primary-content border-0 rounded-lg px-8 transition-all duration-200 hover:scale-105 shadow-lg hover:shadow-xl"
      phx-click={@event}
      phx-value-id={@value}
    >
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7">
        </path>
      </svg>
      {render_slot(@inner_block)}
    </button>
    """
  end
end
