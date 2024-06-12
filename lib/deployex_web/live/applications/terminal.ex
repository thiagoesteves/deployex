defmodule DeployexWeb.ApplicationsLive.Terminal do
  use DeployexWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= "#{@title} [#{@id}]" %>
        <:subtitle>File: <%= @app_path %></:subtitle>
      </.header>

      <div
        id="topics"
        class="bg-gray-50 max-h-50 overflow-y-auto scroll-auto w-full mt-5"
        style="height: 100vh;"
        phx-update="stream"
        phx-window-keydown="key_down"
        phx-target={@myself}
      >
        <%= for {dom_id, text} <- @streams.text do %>
          <p id={dom_id} class={["text-xs font-light", text.color]}>
            <%= text.msg %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(:app_path, "")
      |> assign(:line_counter, 0)
      |> assign(:last_msg, nil)
      |> assign(:terminal_process, nil)
      |> stream(:text, [])

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> handle_terminal_update()

    {:ok, socket}
  end

  defp handle_terminal_update(%{assigns: %{id: _id, current_log: nil}} = socket) do
    command =
      """
      export RELEASE_NODE_SUFFIX=-1
      /tmp/deployex/varlib/service/myphoenixapp/1/current/bin/myphoenixapp remote
      """

    {:ok, _pid, process} = :exec.run_link("#{command}", [:stdin, :stdout])

    socket
    |> assign(:terminal_process, process)
  end

  defp handle_terminal_update(
         %{
           assigns: %{
             current_log: {_type, os_process, message},
             line_counter: line_counter,
             terminal_process: process
           }
         } = socket
       ) when os_process == process do
    messages =
      message
      |> String.split(["\n", "\r"], trim: true)
      |> Enum.with_index(fn element, index ->
        color = log_color("debug")

        %{id: line_counter + index, msg: element, color: color}
      end)

    update_line_counter = line_counter + length(messages)

    socket
    |> assign(:line_counter, update_line_counter)
    |> assign(:last_msg, Enum.at(messages, -1))
    |> stream(:text, messages)
  end

  defp handle_terminal_update(socket) do
    socket
  end

  @impl true
  def handle_event("key_down", %{"key" => key}, socket) when key in ["Shift", "Tab", "ArrowUp"] do
    {:noreply, socket}
  end

  def handle_event(
        "key_down",
        %{"key" => "Backspace"},
        %{assigns: %{terminal_process: terminal_process, last_msg: last_msg}} = socket
      ) do
    :exec.send(terminal_process, "\b")

    last_msg = %{last_msg | msg: String.slice(last_msg.msg, 0..-2//1)}

    {:noreply,
     socket
     |> assign(:last_msg, last_msg)
     |> stream(:text, [last_msg])}
  end

  def handle_event(
        "key_down",
        %{"key" => "Enter"},
        %{assigns: %{terminal_process: terminal_process}} = socket
      ) do
    :exec.send(terminal_process, "\n")

    {:noreply,
     socket
     |> assign(:command, "")}
  end

  def handle_event(
        "key_down",
        %{"key" => key},
        %{assigns: %{terminal_process: terminal_process, last_msg: last_msg}} = socket
      ) do
    :exec.send(terminal_process, key)

    last_msg = %{last_msg | msg: last_msg.msg <> key}

    {:noreply,
     socket
     |> assign(:last_msg, last_msg)
     |> stream(:text, [last_msg])}
  end

  # https://stackoverflow.com/questions/66010467/detect-key-combinations-in-phoenix-liveview-e-g-cmd-f
  # https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797

  defp log_color("debug"), do: "text-gray-700"
end
