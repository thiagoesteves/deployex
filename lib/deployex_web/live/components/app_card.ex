defmodule DeployexWeb.Components.AppCard do
  @moduledoc false
  use Phoenix.Component

  # NOTE: This structure is derived from the Deployex.Status structure
  attr :supervisor, :boolean, required: true
  attr :status, :atom, required: true
  attr :instance, :integer, required: true
  attr :crash_restart_count, :integer, required: true
  attr :force_restart_count, :integer, required: true
  attr :name, :string, required: true
  attr :version, :string, required: true
  attr :uptime, :string, required: true
  attr :otp, :atom, required: true
  attr :tls, :atom, required: true
  attr :last_deployment, :atom, required: true
  attr :last_ghosted_version, :string, required: true
  attr :restart_path, :string, required: true

  def content(assigns) do
    ~H"""
    <div :if={@supervisor}></div>

    <div
      id={"button-#{@name}"}
      class={[app_background(@supervisor, @status), "rounded-lg border border-black mt-2"]}
    >
      <div class="flex flex-col rounded mb-3">
        <.header_card
          status={@status}
          version={@version}
          instance={@instance}
          supervisor={@supervisor}
          restart_path={@restart_path}
        />

        <h3 class="font-mono text-center text-xl text-black font-bold"><%= "#{@name}" %></h3>

        <p :if={@supervisor == false} class="flex  tracking-tight  pt-3   justify-between">
          <span class="text-xs font-bold ml-3">Instance</span>
          <span class="bg-gray-100 text-white-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-white border border-gray-500">
            <%= @instance %>
          </span>
        </p>

        <p class="flex  tracking-tight  pt-3   justify-between">
          <span class="text-xs font-bold ml-3">OTP-Nodes</span>
          <.connected? status={@otp} />
        </p>

        <p :if={@supervisor} class="flex tracking-tight pt-3  justify-between ">
          <span class=" text-xs font-bold ml-3">mTLS</span>
          <.supported? status={@tls} />
        </p>

        <p :if={@last_deployment} class="flex tracking-tight pt-3 justify-between">
          <span class="text-xs font-bold ml-3">Last deployment</span>
          <.deployment deployment={@last_deployment} />
        </p>

        <p :if={@supervisor == false} class="flex  tracking-tight  pt-3   justify-between">
          <span class="text-xs font-bold ml-3">Crash Restart</span>
          <.restarts restarts={@crash_restart_count} />
        </p>

        <p :if={@supervisor == false} class="flex  tracking-tight  pt-3   justify-between">
          <span class="text-xs font-bold ml-3">Force Restart</span>
          <.restarts restarts={@force_restart_count} />
        </p>

        <p
          :if={@supervisor and @last_ghosted_version}
          class="flex tracking-tight pt-3 justify-between"
        >
          <span class="text-xs font-bold ml-3 ">Last ghosted version</span>
          <span class="bg-yellow-100 text-yellow-800 text-xs font-medium me-2 px-5 py-0.5 rounded dark:bg-gray-700 dark:text-yellow-300 border border-yellow-300">
            <%= @last_ghosted_version %>
          </span>
        </p>

        <p class="flex tracking-tight pt-3 justify-between">
          <span class="text-xs font-bold ml-3 ">uptime</span>
          <span class="bg-blue-100 text-blue-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-blue-400 border border-blue-400">
            <%= @uptime %>
          </span>
        </p>

        <p class="flex  tracking-tight  pt-3   justify-between">
          <button
            id={"app-log-stdout-#{@instance}"}
            phx-click="app-log-click"
            phx-value-instance={@instance}
            phx-value-std="stdout"
            type="button"
            class="ml-2 me-2 mb-2 text-white bg-gradient-to-r from-green-400 via-green-500 to-green-600 hover:bg-gradient-to-br focus:ring-4 focus:outline-none focus:ring-green-300 dark:focus:ring-green-800 rounded-lg text-sm px-2 py-1 text-center"
          >
            stdout
          </button>

          <button
            id={"app-terminal-#{@instance}"}
            phx-click="app-terminal-click"
            phx-value-instance={@instance}
            phx-value-std="terminal"
            type="button"
            class="ml-2  me-2 mb-2 text-white bg-gradient-to-r from-gray-500 to-gray-800 font-medium rounded-lg text-sm px-5 py-2.5 text-center"
          >
            <svg
              width="16px"
              height="16px"
              viewBox="0 0 15 15"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M3.5 4.5L6.5 7.5L3.5 10.5M8 10.5H12M1.5 1.5H13.5C14.0523 1.5 14.5 1.94772 14.5 2.5V12.5C14.5 13.0523 14.0523 13.5 13.5 13.5H1.5C0.947716 13.5 0.5 13.0523 0.5 12.5V2.5C0.5 1.94772 0.947715 1.5 1.5 1.5Z"
                stroke="#FFFFFF"
              />
            </svg>
          </button>

          <button
            id={"app-log-stderr-#{@instance}"}
            phx-click="app-log-click"
            phx-value-instance={@instance}
            phx-value-std="stderr"
            type="button"
            class="me-2 mb-2 text-white bg-gradient-to-r from-red-400 via-red-500 to-red-600 hover:bg-gradient-to-br focus:ring-4 focus:outline-none focus:ring-red-300 dark:focus:ring-red-800 font-medium rounded-lg text-sm px-2 py-1 text-center"
          >
            stderr
          </button>

          <button
            id={"app-versions-#{@instance}"}
            phx-click="app-versions-click"
            phx-value-instance={@instance}
            type="button"
            class="me-2 mb-2 text-white bg-gradient-to-r from-blue-400 via-blue-500 to-blue-600 hover:bg-gradient-to-br focus:ring-4 focus:outline-none focus:ring-blue-300 dark:focus:ring-blue-800 font-medium rounded-lg text-sm px-2 py-1 text-center"
          >
            versions
          </button>
        </p>
      </div>
    </div>

    <div :if={@supervisor}></div>
    """
  end

  defp connected?(assigns) do
    ~H"""
    <%= if @status == :connected do %>
      <span class="bg-green-100 text-green-800 text-xs font-medium me-2 px-2 py-0.5 rounded dark:bg-gray-700 dark:text-green-400 border border-green-400">
        CONNECTED
      </span>
    <% else %>
      <span class="bg-red-100 text-red-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-red-400 border border-red-400">
        NOT CONNECTED
      </span>
    <% end %>
    """
  end

  defp supported?(assigns) do
    ~H"""
    <%= if @status == :supported do %>
      <span class="bg-green-100 text-green-800 text-xs font-medium me-2 px-2 py-0.5 rounded dark:bg-gray-700 dark:text-green-400 border border-green-400">
        SUPPORTED
      </span>
    <% else %>
      <span class="bg-red-100 text-red-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-red-400 border border-red-400">
        NOT SUPPORTED
      </span>
    <% end %>
    """
  end

  defp restarts(assigns) do
    ~H"""
    <%= cond do %>
      <% @restarts > 0 -> %>
        <span class="bg-red-100 text-red-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-red-400 border border-red-500 animate-pulse">
          <%= @restarts %>
        </span>
      <% true -> %>
        <span class="bg-gray-100 text-white-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-white border border-gray-500">
          <%= @restarts %>
        </span>
    <% end %>
    """
  end

  defp deployment(assigns) do
    ~H"""
    <%= if @deployment == "full_deployment" do %>
      <span class="bg-blue-100 text-blue-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-blue-400 border border-blue-400">
        FULL
      </span>
    <% else %>
      <span class="bg-indigo-100 text-indigo-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-indigo-400 border border-indigo-400">
        HOT UPGRADE
      </span>
    <% end %>
    """
  end

  defp app_background(true, _status) do
    "bg-gradient-to-r from-cyan-400 to-blue-400"
  end

  defp app_background(_supervisor, :running) do
    "bg-gradient-to-r from-cyan-200 to-yellow-100"
  end

  defp app_background(_supervisor, _status) do
    "bg-gray-400"
  end

  defp restart_buttom(assigns) do
    ~H"""
    <.link id={"app-restart-#{@instance}"} patch={@restart_path}>
      <button
        type="button"
        class="ml-2 me-2 mb-2 text-white bg-gradient-to-r from-red-400 via-red-500 to-red-600 hover:bg-gradient-to-br focus:ring-4 focus:outline-none focus:ring-red-300 dark:focus:ring-red-800 rounded-lg text-sm px-2 py-1 text-center"
      >
        <svg
          width="32px"
          height="16px"
          viewBox="0 0 100 100"
          xmlns="http://www.w3.org/2000/svg"
          version="1.1"
        >
          <g style="fill:none;stroke:#FFFFFF;stroke-width:12px;stroke-linecap:round;stroke-linejoin:round;">
            <path d="m 50,10 0,35" />
            <path d="M 20,29 C 4,52 15,90 50,90 85,90 100,47 74,20" />
          </g>
          <path style="fill:#FFFFFF;" d="m 2,21 29,-2 2,29" />
        </svg>
      </button>
    </.link>
    """
  end

  defp header_card(assigns) do
    default_spec_class = "font-mono text-sm text-center p-2 border-b-2 border-black rounded-t-lg"

    class =
      if assigns.supervisor do
        default_spec_class
      else
        "flex items-center justify-between font-mono text-sm text-center p-2 border-b-2 border-black rounded-t-lg"
      end

    assigns =
      assigns
      |> assign(class: class)
      |> assign(default_spec_class: default_spec_class)

    ~H"""
    <%= cond do %>
      <% @status == :running and @version != nil -> %>
        <div class={[@class, "bg-gradient-to-t from-green-400 to-green-600"]}>
          <.restart_buttom
            :if={@supervisor == false}
            instance={@instance}
            restart_path={@restart_path}
          />
          <%= @version %> [running]
        </div>
      <% @status == :pre_commands and @version != nil -> %>
        <div class={[@class, "bg-gradient-to-t from-yellow-100 to-yellow-600"]}>
          <.restart_buttom
            :if={@supervisor == false}
            instance={@instance}
            restart_path={@restart_path}
          />
          <%= @version %> [pre-commands]
        </div>
      <% @status == :starting and @version != nil -> %>
        <div class={[@class, "bg-gradient-to-t from-yellow-400 to-yellow-600"]}>
          <.restart_buttom
            :if={@supervisor == false}
            instance={@instance}
            restart_path={@restart_path}
          />
          <%= @version %> [starting]
        </div>
      <% true -> %>
        <div class={[@default_spec_class, "bg-gradient-to-t from-gray-400 to-gray-600 animate-pulse"]}>
          version not set
        </div>
    <% end %>
    """
  end
end
