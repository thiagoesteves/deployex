defmodule DeployexWeb.UI.Meter do
  @moduledoc """
  A small labeled usage bar, like the host CPU and memory in the top bar.
  """
  use Phoenix.Component

  @doc """
  Renders a percentage as a bar: blue below `warn_at`, amber from `warn_at`, red from `alert_at`.
  """
  attr :label, :string, required: true, doc: "the short visible label, like CPU"
  attr :name, :string, required: true, doc: "the accessible name, like Host CPU"
  attr :value, :integer, default: nil, doc: "the percentage, nil before the first reading"
  attr :detail, :string, default: nil, doc: "the capacity after the value, like 2 cores"
  attr :warn_at, :integer, default: 75
  attr :alert_at, :integer, default: 90
  attr :rest, :global

  def meter(assigns) do
    assigns =
      assigns
      |> assign(:fill, fill(assigns.value))
      |> assign(:tone, tone(assigns.value, assigns.warn_at, assigns.alert_at))

    ~H"""
    <div class="inline-flex items-center gap-2 text-xs" {@rest}>
      <span class="font-semibold text-muted">{@label}</span>
      <span
        role="meter"
        aria-label={@name}
        aria-valuemin="0"
        aria-valuemax="100"
        aria-valuenow={@fill}
        aria-valuetext={value_text(@value, @detail)}
        class="block h-1.5 w-15 overflow-hidden rounded-full bg-base-300"
      >
        <span
          class={[
            "block h-full rounded-full transition-[width] duration-500 motion-reduce:transition-none",
            @tone
          ]}
          style={"width: #{@fill}%"}
        />
      </span>
      <span class="min-w-8 text-right font-mono font-semibold tabular-nums">
        {if @value, do: "#{@value}%", else: "--"}
      </span>
      <span :if={@detail} class="text-muted">{@detail}</span>
    </div>
    """
  end

  defp fill(nil), do: 0
  defp fill(value), do: value |> max(0) |> min(100)

  defp tone(nil, _warn_at, _alert_at), do: "bg-info"
  defp tone(value, _warn_at, alert_at) when value >= alert_at, do: "bg-error"
  defp tone(value, warn_at, _alert_at) when value >= warn_at, do: "bg-warning"
  defp tone(_value, _warn_at, _alert_at), do: "bg-info"

  defp value_text(nil, _detail), do: "No reading yet"
  defp value_text(value, nil), do: "#{value}%"
  defp value_text(value, detail), do: "#{value}% of #{detail}"
end
