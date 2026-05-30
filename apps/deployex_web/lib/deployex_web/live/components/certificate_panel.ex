defmodule DeployexWeb.Components.CertificatePanel do
  @moduledoc """
  Inline certificate summary panel. Shown below card content when a certificate is present.
  `certificate` is a normalized map (see ApplicationsLive.normalize_certificate/1).
  `event` is the phx-click event name to open the detail modal.
  `name` is passed as phx-name-id to identify which cert to show in the modal.
  """
  use DeployexWeb, :html
  use Phoenix.Component

  @warn_days 30

  attr :certificate, :map, required: true
  attr :event, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true

  def content(assigns) do
    expires_in_days = assigns.certificate.expires_in_days
    expiring_soon? = expires_in_days && expires_in_days < @warn_days
    domain_count = length(assigns.certificate.domains || [])

    assigns =
      assigns
      |> assign(:expiring_soon?, expiring_soon?)
      |> assign(:expires_in_days, expires_in_days)
      |> assign(:domain_count, domain_count)

    ~H"""
    <div class={[
      "mt-4 border rounded-xl p-4",
      if(@expiring_soon?,
        do: "bg-error/5 border-error/30",
        else: "bg-base-200/50 border-base-300"
      )
    ]}>
      <!-- Panel header -->
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <svg
            class={["w-4 h-4", if(@expiring_soon?, do: "text-error", else: "text-info")]}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
            />
          </svg>
          <span class="text-sm font-medium text-base-content">{@label}</span>
          <span class={[
            "text-xs px-2 py-0.5 rounded-full font-medium",
            if(@expiring_soon?,
              do: "bg-error/15 text-error border border-error/20",
              else: "bg-success/15 text-success border border-success/20"
            )
          ]}>
            {if @expiring_soon?, do: "expires soon", else: "active"}
          </span>
        </div>

        <button
          phx-click={@event}
          phx-value-name={@name}
          type="button"
          class="btn btn-xs bg-base-100 border-base-300 hover:bg-base-200 transition-all"
        >
          View details
        </button>
      </div>
      
    <!-- Summary fields -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
        <div class="bg-base-100 border border-base-300 rounded-lg p-2.5">
          <div class="text-xs text-base-content/60 mb-1">Issuer</div>
          <div class="text-sm font-medium truncate">{@certificate.issuer || "—"}</div>
        </div>

        <div class="bg-base-100 border border-base-300 rounded-lg p-2.5">
          <div class="text-xs text-base-content/60 mb-1">Expires in</div>
          <div class={[
            "text-sm font-semibold",
            if(@expiring_soon?, do: "text-error", else: "text-success")
          ]}>
            {if @expires_in_days, do: "#{@expires_in_days} days", else: "—"}
          </div>
        </div>

        <div class="bg-base-100 border border-base-300 rounded-lg p-2.5">
          <div class="text-xs text-base-content/60 mb-1">Domains</div>
          <div class="text-sm font-medium">
            {if @domain_count > 0, do: "#{@domain_count} covered", else: "—"}
          </div>
        </div>

        <div class="bg-base-100 border border-base-300 rounded-lg p-2.5">
          <div class="text-xs text-base-content/60 mb-1">Public key</div>
          <div class="text-sm font-medium">
            <%= cond do %>
              <% @certificate.public_key_type && @certificate.public_key_size -> %>
                {@certificate.public_key_type} {@certificate.public_key_size} bits
              <% @certificate.public_key_type -> %>
                {@certificate.public_key_type}
              <% true -> %>
                —
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
