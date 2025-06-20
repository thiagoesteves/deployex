defmodule DeployexWeb.Components.NavMenu do
  @moduledoc false
  use DeployexWeb, :live_component

  alias DeployexWeb.Cache.UiSettings

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@id}"} class="bg-gray-300">
      <div class="flex flex-1 min-h-screen">
        <div class="hidden md:flex md:flex-col" style={nav_bar_width(@ui_settings.nav_menu_collapsed)}>
          <div class="flex flex-col flex-grow pt-5 bg-gray-300">
            <div class="flex items-center flex-shrink-0">
              <div class={icon_wrapper_class()}>
                <svg
                  class="w-10 h-10 p-2 text-black rounded-full"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  stroke="currentColor"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  viewBox="0 0 24 24"
                >
                  <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"></path>
                </svg>
              </div>

              <span
                :if={@ui_settings.nav_menu_collapsed}
                class="self-center text-xl font-semibold whitespace-nowrap dark:text-black"
              >
                DeployEx
              </span>
              <.nav_menu_button collapsed={@ui_settings.nav_menu_collapsed} target={@myself} />
            </div>

            <div class="px-2 mt-4">
              <hr class="border-gray-400" />
            </div>

            <div class="flex flex-col flex-1 mt-6">
              <div class="space-y-4">
                <nav class="flex-1 space-y-2">
                  <a href={~p"/applications"} class={href_wrapper_class()}>
                    <div class={icon_wrapper_class()}>
                      <svg
                        class="flex-shrink-0 w-5 h-5 transition-all"
                        xmlns="http://www.w3.org/2000/svg"
                        class="w-6 h-6"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
                        />
                      </svg>
                    </div>

                    <div :if={@ui_settings.nav_menu_collapsed} class="ml-2 self-center font-semibold">
                      Applications
                    </div>
                  </a>

                  <a href={~p"/logs/live"} class={href_wrapper_class()}>
                    <div class={icon_wrapper_class()}>
                      <svg
                        class="flex-shrink-0 w-5 h-5"
                        width="24px"
                        height="24px"
                        viewBox="0 0 24 24"
                        version="1.1"
                        fill="none"
                        stroke="currentColor"
                      >
                        <path d="M5.98959236,4.92893219 C6.28248558,5.22182541 6.28248558,5.69669914 5.98959236,5.98959236 C2.67013588,9.30904884 2.67013588,14.6909512 5.98959236,18.0104076 C6.28248558,18.3033009 6.28248558,18.7781746 5.98959236,19.0710678 C5.69669914,19.363961 5.22182541,19.363961 4.92893219,19.0710678 C1.02368927,15.1658249 1.02368927,8.83417511 4.92893219,4.92893219 C5.22182541,4.63603897 5.69669914,4.63603897 5.98959236,4.92893219 Z M19.0710678,4.92893219 C22.9763107,8.83417511 22.9763107,15.1658249 19.0710678,19.0710678 C18.7781746,19.363961 18.3033009,19.363961 18.0104076,19.0710678 C17.7175144,18.7781746 17.7175144,18.3033009 18.0104076,18.0104076 C21.3298641,14.6909512 21.3298641,9.30904884 18.0104076,5.98959236 C17.7175144,5.69669914 17.7175144,5.22182541 18.0104076,4.92893219 C18.3033009,4.63603897 18.7781746,4.63603897 19.0710678,4.92893219 Z M8.81801948,7.75735931 C9.1109127,8.05025253 9.1109127,8.52512627 8.81801948,8.81801948 C7.06066017,10.5753788 7.06066017,13.4246212 8.81801948,15.1819805 C9.1109127,15.4748737 9.1109127,15.9497475 8.81801948,16.2426407 C8.52512627,16.5355339 8.05025253,16.5355339 7.75735931,16.2426407 C5.41421356,13.8994949 5.41421356,10.1005051 7.75735931,7.75735931 C8.05025253,7.46446609 8.52512627,7.46446609 8.81801948,7.75735931 Z M16.2426407,7.75735931 C18.5857864,10.1005051 18.5857864,13.8994949 16.2426407,16.2426407 C15.9497475,16.5355339 15.4748737,16.5355339 15.1819805,16.2426407 C14.8890873,15.9497475 14.8890873,15.4748737 15.1819805,15.1819805 C16.9393398,13.4246212 16.9393398,10.5753788 15.1819805,8.81801948 C14.8890873,8.52512627 14.8890873,8.05025253 15.1819805,7.75735931 C15.4748737,7.46446609 15.9497475,7.46446609 16.2426407,7.75735931 Z M12,10.5 C12.8284271,10.5 13.5,11.1715729 13.5,12 C13.5,12.8284271 12.8284271,13.5 12,13.5 C11.1715729,13.5 10.5,12.8284271 10.5,12 C10.5,11.1715729 11.1715729,10.5 12,10.5 Z">
                        </path>
                      </svg>
                    </div>

                    <div
                      :if={@ui_settings.nav_menu_collapsed}
                      class="ml-2 self-center  font-semibold "
                    >
                      Live Logs
                    </div>
                  </a>

                  <a href={~p"/logs/history"} class={href_wrapper_class()}>
                    <div class={icon_wrapper_class()}>
                      <svg
                        class="flex-shrink-0 w-5 h-5"
                        viewBox="0 0 512 512.44"
                        version="1.1"
                        fill="currentColor"
                        stroke="currentColor"
                      >
                        <path
                          fill="currentColor"
                          d="M216.81 155.94c0-10.96 8.88-19.84 19.84-19.84 10.95 0 19.83 8.88 19.83 19.84v120.75l82.65 36.33c10.01 4.41 14.56 16.1 10.15 26.11-4.41 10.02-16.1 14.56-26.11 10.15l-93.5-41.1c-7.51-2.82-12.86-10.07-12.86-18.57V155.94zM9.28 153.53c-.54-1.88-.83-3.87-.83-5.92l.16-73.41c0-11.84 9.59-21.43 21.43-21.43 11.83 0 21.43 9.59 21.43 21.43l-.06 27.86a255.053 255.053 0 0144.08-45.53c16.78-13.47 35.57-25.04 56.18-34.24 64.6-28.81 134.7-28.73 195.83-5.31 60.67 23.24 112.56 69.47 141.51 133.25.56 1.01 1.03 2.07 1.41 3.17 28.09 64.15 27.83 133.6 4.6 194.21-22.33 58.29-65.87 108.46-125.8 137.98-.38.22-.76.42-1.16.62-12.44 6.14-25.46 11.26-38.74 15.3-4.96 1.46-10.12.99-14.68-1.46-15.1-8.13-12.86-30.46 3.53-35.45 8.78-2.7 17.32-5.87 25.67-9.6.41-.21.84-.4 1.27-.58 2-.91 3.99-1.85 5.96-2.82.53-.26 1.07-.5 1.62-.71 50.62-25.1 87.42-67.61 106.34-116.98 19.93-52.04 20.04-111.64-4.41-166.46l-.01-.02c-24.46-54.82-68.84-94.54-120.82-114.45-52.04-19.94-111.63-20.04-166.45 4.41a217.791 217.791 0 00-47.75 29.11 216.133 216.133 0 00-37.71 39.04l17.1-.97c11.83-.65 21.96 8.42 22.61 20.26.65 11.83-8.42 21.96-20.26 22.61l-69.71 3.94c-11.02.6-20.56-7.21-22.34-17.85zm237.66 358.9c17.55.55 26.69-20.55 14.26-32.98-3.57-3.45-7.9-5.35-12.86-5.56-11.92-.39-23.48-1.72-35.19-4.01-7.52-1.44-14.84 1.44-19.39 7.59-8.15 11.46-1.97 27.43 11.85 30.22a256.37 256.37 0 0041.33 4.74zm-119.12-34.22c11.75 6.79 26.54-.08 28.81-13.5 1.23-7.97-2.34-15.6-9.26-19.74-10.27-5.99-19.83-12.71-28.99-20.28-13.76-11.34-34.16.32-31.36 17.95.81 4.7 3.05 8.59 6.69 11.68a255.166 255.166 0 0034.11 23.89zm-88.67-86.32c8.88 14.11 30.17 11.17 34.88-4.84 1.51-5.36.76-10.83-2.17-15.57-6.29-10.03-11.7-20.52-16.31-31.43-6.2-14.74-26.7-15.97-34.56-2.04-2.94 5.15-3.3 11.48-1 16.94 5.36 12.77 11.8 25.21 19.16 36.94zM.66 274.2c.62 8.63 6.81 15.71 15.27 17.51 12.64 2.53 23.99-7.36 23.19-20.23-.85-11.87-.73-23.54.32-35.4.59-7.04-2.49-13.66-8.31-17.67-12.22-8.25-28.69-.5-30.08 14.17a257.06 257.06 0 00-.39 41.62z"
                        />
                      </svg>
                    </div>

                    <div
                      :if={@ui_settings.nav_menu_collapsed}
                      class="ml-2 self-center  font-semibold "
                    >
                      History Logs
                    </div>
                  </a>

                  <a href={~p"/embedded-observer"} class={href_wrapper_class()}>
                    <div class={icon_wrapper_class()}>
                      <svg
                        class="flex-shrink-0 w-6 h-6"
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      >
                        <path stroke="none" d="M0 0h24v24H0z" fill="none" /><path d="M20 18a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M8 18a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M8 6a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M20 6a2 2 0 1 0 -4 0a2 2 0 0 0 4 0z" /><path d="M6 8v8" /><path d="M18 16v-8" /><path d="M8 6h8" /><path d="M16 18h-8" /><path d="M7.5 7.5l9 9" /><path d="M7.5 16.5l9 -9" />
                      </svg>
                    </div>

                    <div
                      :if={@ui_settings.nav_menu_collapsed}
                      class="ml-1 self-center  font-semibold "
                    >
                      Observer Web
                    </div>
                  </a>

                  <a href={~p"/terminal"} class={href_wrapper_class()}>
                    <div class={icon_wrapper_class()}>
                      <svg
                        class="flex-shrink-0 w-5 h-5"
                        width="24px"
                        height="24px"
                        viewBox="0 0 16 16"
                        xmlns="http://www.w3.org/2000/svg"
                        version="1.1"
                        fill="none"
                        stroke="currentColor"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="1.5"
                      >
                        <rect height="10.5" width="12.5" y="2.75" x="1.75" />
                        <path d="m8.75 10.25h2.5m-6.5-4.5 2.5 2.25-2.5 2.25" />
                      </svg>
                    </div>

                    <div
                      :if={@ui_settings.nav_menu_collapsed}
                      class="ml-2 self-center  font-semibold "
                    >
                      Host Terminal
                    </div>
                  </a>

                  <a href={~p"/applications/deployex/docs"} class={href_wrapper_class()}>
                    <div class={icon_wrapper_class()}>
                      <svg
                        class="flex-shrink-0 w-5 h-5"
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.746 0 3.332.477 4.5 1.253v13C20.168 18.477 18.582 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
                        />
                      </svg>
                    </div>

                    <div
                      :if={@ui_settings.nav_menu_collapsed}
                      class="ml-2 self-center  font-semibold "
                    >
                      Docs
                    </div>
                  </a>
                </nav>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event(
        "collpase-click",
        %{"collpased" => "true"},
        %{assigns: %{ui_settings: ui_settings}} = socket
      ) do
    updated_options = %{ui_settings | nav_menu_collapsed: false}

    UiSettings.set(updated_options)

    {:noreply, assign(socket, :ui_settings, updated_options)}
  end

  def handle_event(
        "collpase-click",
        %{"collpased" => "false"},
        %{assigns: %{ui_settings: ui_settings}} = socket
      ) do
    updated_options = %{ui_settings | nav_menu_collapsed: true}

    UiSettings.set(updated_options)

    {:noreply, assign(socket, :ui_settings, updated_options)}
  end

  defp nav_menu_button(assigns) do
    assigns =
      assigns
      |> assign(rotation_class: if(assigns.collapsed, do: "", else: "rotate-180"))

    ~H"""
    <button
      id="toggle-nav-menu-button"
      phx-click="collpase-click"
      phx-value-collpased={to_string(@collapsed)}
      phx-target={@target}
      class="ml-1 p-2 rounded-lg hover:bg-gray-400"
    >
      <svg
        class={[
          "w-5 h-5 text-gray-700 transition-transform duration-300 ease-in-out",
          @rotation_class
        ]}
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M11 19l-7-7 7-7m8 14l-7-7 7-7"
        >
        </path>
      </svg>
    </button>
    """
  end

  defp href_wrapper_class do
    "flex items-right px-6 py-2.5 text-sm font-medium text-gray-900 transition-all duration-300 ease-in-out hover:text-white hover:bg-indigo-400 rounded-lg group"
  end

  defp icon_wrapper_class, do: "flex"

  defp nav_bar_width(collapsed) do
    if collapsed do
      "width: 12rem;"
    else
      "width: 5rem;"
    end
  end
end
