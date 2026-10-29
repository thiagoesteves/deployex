defmodule DeployexWeb.UI.Icons do
  @moduledoc """
  Inline outline icons from heroicons, with the stroke widths of the design, and the ghost icon.

  An icon takes `currentColor`, so its text color sets it.
  """
  use Phoenix.Component

  @paths %{
    "arrow-left" => ["M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18"],
    "lock-closed" => [
      "M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"
    ],
    "copy" => [
      "M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75"
    ],
    "external" => [
      "M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
    ],
    "arrow-down" => ["M19.5 13.5 12 21m0 0-7.5-7.5M12 21V3"],
    "arrow-up" => ["M4.5 10.5 12 3m0 0 7.5 7.5M12 3v18"],
    "arrow-path" => [
      "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99"
    ],
    "arrow-up-circle" => ["m15 11.25-3-3m0 0-3 3m3-3v7.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"],
    "arrows-in" => [
      "M9 9V4.5M9 9H4.5M9 9 3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5 5.25 5.25"
    ],
    "arrows-out" => [
      "M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
    ],
    "bars" => ["M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"],
    "bell" => [
      "M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0"
    ],
    "book-open" => [
      "M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
    ],
    "check" => ["m4.5 12.75 6 6 9-13.5"],
    "chevron-down" => ["m19.5 8.25-7.5 7.5-7.5-7.5"],
    "chevron-right" => ["m8.25 4.5 7.5 7.5-7.5 7.5"],
    "clock" => ["M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"],
    "command-line" => [
      "m6.75 7.5 3 2.25-3 2.25m4.5 0h3m-9 8.25h13.5A2.25 2.25 0 0 0 21 17.25V6.75A2.25 2.25 0 0 0 18.75 4.5H5.25A2.25 2.25 0 0 0 3 6.75v10.5A2.25 2.25 0 0 0 5.25 21Z"
    ],
    "computer-desktop" => [
      "M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
    ],
    "cube" => [
      "m21 7.5-9-5.25L3 7.5m18 0-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"
    ],
    "eye" => [
      "M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178Z",
      "M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
    ],
    "fire" => [
      "M15.362 5.214A8.252 8.252 0 0 1 12 21 8.25 8.25 0 0 1 6.038 7.047 8.287 8.287 0 0 0 9 9.601a8.983 8.983 0 0 1 3.361-6.867 8.21 8.21 0 0 0 3 2.48Z",
      "M12 18a3.75 3.75 0 0 0 .495-7.468 5.99 5.99 0 0 0-1.925 3.547 5.975 5.975 0 0 1-2.133-1.001A3.75 3.75 0 0 0 12 18Z"
    ],
    "home" => [
      "m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25"
    ],
    "lines" => ["M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12"],
    "logout" => [
      "M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9"
    ],
    "moon" => [
      "M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z"
    ],
    "plus" => ["M12 4.5v15m7.5-7.5h-15"],
    "search" => ["m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"],
    "signal" => [
      "M9.348 14.652a3.75 3.75 0 0 1 0-5.304m5.304 0a3.75 3.75 0 0 1 0 5.304m-7.425 2.121a6.75 6.75 0 0 1 0-9.546m9.546 0a6.75 6.75 0 0 1 0 9.546M5.106 18.894c-3.808-3.807-3.808-9.98 0-13.788m13.788 0c3.808 3.807 3.808 9.98 0 13.788M12 12h.008v.008H12V12Z"
    ],
    "sliders" => [
      "M10.5 6h9.75M10.5 6a1.5 1.5 0 1 1-3 0m3 0a1.5 1.5 0 1 0-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m-9.75 0h9.75"
    ],
    "sun" => [
      "M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z"
    ],
    "warning" => [
      "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
    ],
    "x-circle" => ["m9.75 9.75 4.5 4.5m0-4.5-4.5 4.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"],
    "x-mark" => ["M6 18 18 6M6 6l12 12"]
  }

  @ghost "M12 2a8 8 0 0 0-8 8v12l3-3 2.5 2.5L12 19l2.5 2.5L17 19l3 3V10a8 8 0 0 0-8-8zM7.8 10a1.2 1.6 0 1 0 2.4 0a1.2 1.6 0 1 0-2.4 0zM13.8 10a1.2 1.6 0 1 0 2.4 0a1.2 1.6 0 1 0-2.4 0z"

  @doc """
  Renders an icon by name. Decorative by default: give `label` when the icon carries meaning alone.
  """
  attr :name, :string, required: true
  attr :class, :any, default: "dx-ico"
  attr :stroke, :string, default: "1.8"
  attr :label, :string, default: nil

  attr :gradient, :string,
    default: "dx-ow-logo-gradient",
    doc: "the gradient id, unique on the page"

  attr :rest, :global

  # The Supervision Lens logo of the Observer Web project (Observer.Web.Components.Icons), kept in sync manually
  def icon(%{name: "observer-web"} = assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      role={@label && "img"}
      aria-label={@label}
      aria-hidden={is_nil(@label) && "true"}
      {@rest}
    >
      <defs>
        <linearGradient id={@gradient} x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stop-color="#2563eb" />
          <stop offset="1" stop-color="#06b6d4" />
        </linearGradient>
      </defs>
      <circle cx="10.5" cy="10.5" r="7.5" />
      <line x1="16.2" y1="16.2" x2="21" y2="21" stroke-width="2.4" />
      <line x1="10.5" y1="8" x2="7.2" y2="13" />
      <line x1="10.5" y1="8" x2="13.8" y2="13" />
      <circle cx="10.5" cy="7.6" r="1.7" fill={"url(##{@gradient})"} stroke="none" />
      <circle cx="7.0" cy="13.4" r="1.4" fill="currentColor" stroke="none" />
      <circle cx="14.0" cy="13.4" r="1.4" fill="currentColor" stroke="none" />
    </svg>
    """
  end

  def icon(%{name: "ghost"} = assigns) do
    assigns = assign(assigns, :d, @ghost)

    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      role={@label && "img"}
      aria-label={@label}
      aria-hidden={is_nil(@label) && "true"}
      {@rest}
    >
      <path fill="currentColor" fill-rule="evenodd" d={@d} />
    </svg>
    """
  end

  def icon(assigns) do
    assigns = assign(assigns, :paths, Map.fetch!(@paths, assigns.name))

    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width={@stroke}
      stroke-linecap="round"
      stroke-linejoin="round"
      role={@label && "img"}
      aria-label={@label}
      aria-hidden={is_nil(@label) && "true"}
      {@rest}
    >
      <path :for={d <- @paths} d={d} />
    </svg>
    """
  end

  @doc false
  def names, do: ["ghost", "observer-web" | Map.keys(@paths)]
end
