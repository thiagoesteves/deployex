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
  attr :detail, :string, default: nil, doc: "the capacity, like 2 cores, for the tooltip"
  attr :warn_at, :integer, default: 75
  attr :alert_at, :integer, default: 90
  attr :rest, :global

  def meter(assigns) do
    assigns =
      assigns
      |> assign(:fill, fill(assigns.value))
      |> assign(:tone, tone(assigns.value, assigns.warn_at, assigns.alert_at))

    ~H"""
    <div class="dx-meter" title={title(@name, @value, @detail)} {@rest}>
      <span class="dx-lbl">{@label}</span>
      <span
        class="dx-mbar"
        role="meter"
        aria-label={@name}
        aria-valuemin="0"
        aria-valuemax="100"
        aria-valuenow={@fill}
        aria-valuetext={value_text(@value, @detail)}
      >
        <i style={"width: #{@fill}%; background: #{@tone}"}></i>
      </span>
      <b>{if @value, do: "#{@value}%", else: "--"}</b>
    </div>
    """
  end

  defp fill(nil), do: 0
  defp fill(value), do: value |> max(0) |> min(100)

  defp tone(nil, _warn_at, _alert_at), do: "var(--dx-info)"
  defp tone(value, _warn_at, alert_at) when value >= alert_at, do: "var(--dx-error)"
  defp tone(value, warn_at, _alert_at) when value >= warn_at, do: "var(--dx-warning)"
  defp tone(_value, _warn_at, _alert_at), do: "var(--dx-info)"

  defp title(name, nil, _detail), do: "#{name}, no reading yet"
  defp title(name, value, nil), do: "#{name} #{value} percent"
  defp title(name, value, detail), do: "#{name} #{value} percent of #{detail}"

  defp value_text(nil, _detail), do: "No reading yet"
  defp value_text(value, nil), do: "#{value}%"
  defp value_text(value, detail), do: "#{value}% of #{detail}"
end
