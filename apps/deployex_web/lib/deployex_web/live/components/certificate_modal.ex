defmodule DeployexWeb.Components.CertificateModal do
  @moduledoc """
  Modal component for displaying certificate details
  """
  use DeployexWeb, :html
  use Phoenix.Component

  attr :id, :string, required: true
  attr :certificate, :map, required: true
  attr :on_cancel, :string, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={"#{@id}-modal"}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div class="modal modal-open">
        <div class="modal-box max-w-lg">
          <h3 class="font-bold text-lg mb-4">mTLS Certificate Details</h3>

          <dl class="grid grid-cols-2 gap-3 text-sm">
            <div class="bg-base-200 rounded-lg p-3">
              <dt class="text-xs text-base-content/60 mb-1">Issuer</dt>
              <dd class="font-medium truncate">{@certificate.issuer || "—"}</dd>
            </div>
            <div class="bg-base-200 rounded-lg p-3">
              <dt class="text-xs text-base-content/60 mb-1">Serial</dt>
              <dd class="font-mono text-xs truncate">{@certificate.serial || "—"}</dd>
            </div>
            <div class="bg-base-200 rounded-lg p-3">
              <dt class="text-xs text-base-content/60 mb-1">Version</dt>
              <dd class="font-medium">{@certificate.version || "—"}</dd>
            </div>
            <div class="bg-base-200 rounded-lg p-3">
              <dt class="text-xs text-base-content/60 mb-1">Public Key</dt>
              <dd class="font-medium">
                <%= if @certificate.public_key_type do %>
                  {@certificate.public_key_type} {@certificate.public_key_size} bits
                <% else %>
                  —
                <% end %>
              </dd>
            </div>
            <div class={[
              "bg-base-200 rounded-lg p-3",
              @certificate.expires_in_days && @certificate.expires_in_days < 30 &&
                "border border-error/50"
            ]}>
              <dt class="text-xs text-base-content/60 mb-1">Expires In</dt>
              <dd class={[
                "font-medium",
                @certificate.expires_in_days && @certificate.expires_in_days < 30 &&
                  "text-error"
              ]}>
                <%= if @certificate.expires_in_days do %>
                  {@certificate.expires_in_days} days
                <% else %>
                  —
                <% end %>
              </dd>
            </div>
          </dl>

          <%= if @certificate.domains && length(@certificate.domains) > 0 do %>
            <div class="mt-4">
              <dt class="text-xs text-base-content/60 mb-2">Covered Domains</dt>
              <div class="flex flex-wrap gap-2">
                <%= for domain <- @certificate.domains do %>
                  <span class="badge badge-ghost badge-sm font-mono">{domain}</span>
                <% end %>
              </div>
            </div>
          <% end %>

          <div class="modal-action">
            <button phx-click={@on_cancel} class="btn btn-sm">Close</button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click={@on_cancel}></div>
      </div>
    </div>
    """
  end
end
