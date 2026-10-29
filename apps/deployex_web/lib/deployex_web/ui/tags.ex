defmodule DeployexWeb.UI.Tags do
  @moduledoc """
  Small labels: the status with its dot, the last deploy tag, and the language or system icon.

  A status always has its text next to the color, and every ghosted state uses the ghost icon.
  """
  use Phoenix.Component

  alias DeployexWeb.UI.Icons

  @tones %{
    success: "var(--dx-success-text)",
    warning: "var(--dx-warning-text)",
    error: "var(--dx-error-text)",
    info: "var(--dx-info-text)",
    muted: "var(--dx-muted)"
  }

  @doc """
  The tone colors, for markup that colors its own text.
  """
  @spec tone(atom()) :: String.t()
  def tone(tone), do: Map.fetch!(@tones, tone)

  attr :text, :string, required: true
  attr :tone, :atom, required: true, values: [:success, :warning, :error, :info, :muted]
  attr :class, :any, default: nil

  def status(assigns) do
    ~H"""
    <span class={["dx-status", @class]} style={"color: #{tone(@tone)}"}>
      <span class="dx-dot"></span>{@text}
    </span>
    """
  end

  attr :type, :atom, required: true, values: [:full, :hot, :ghosted, :failed]
  attr :label, :string, default: nil

  def deploy_tag(assigns) do
    ~H"""
    <span class={["dx-dtag", tag_class(@type)]}>
      <Icons.icon :if={@type == :full} name="cube" stroke="2" class={nil} />
      <Icons.icon :if={@type == :hot} name="fire" stroke="2" class={nil} />
      <Icons.icon :if={@type == :ghosted} name="ghost" class="dx-gh" />
      <Icons.icon :if={@type == :failed} name="x-circle" stroke="2" class={nil} />
      {@label || default_label(@type)}
    </span>
    """
  end

  attr :name, :string, required: true, doc: "elixir, erlang, gleam, linux, macos or deployex"
  attr :label, :string, default: nil
  attr :small, :boolean, default: false

  attr :logo, :string,
    default: nil,
    doc: "the app's own logo as a data URI, shown instead of the language"

  def lang(%{logo: logo} = assigns) when is_binary(logo) do
    ~H"""
    <img src={@logo} alt="" class={["dx-lang object-contain", @small && "dx-lang-sm"]} />
    """
  end

  def lang(assigns) do
    ~H"""
    <span
      class={["dx-lang", "dx-lang-#{@name}", @small && "dx-lang-sm"]}
      role={@label && "img"}
      aria-label={@label}
      aria-hidden={is_nil(@label) && "true"}
      title={@label}
    ></span>
    """
  end

  defp tag_class(:full), do: "dx-dtag-full"
  defp tag_class(:hot), do: "dx-dtag-hot"
  defp tag_class(_type), do: "dx-dtag-fail"

  defp default_label(:full), do: "full"
  defp default_label(:hot), do: "hot"
  defp default_label(:ghosted), do: "ghosted"
  defp default_label(:failed), do: "failed"
end
