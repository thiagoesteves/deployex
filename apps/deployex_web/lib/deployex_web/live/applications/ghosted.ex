defmodule DeployexWeb.ApplicationsLive.Ghosted do
  use DeployexWeb, :live_component

  alias Deployer.Status

  attr :name, :string, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {"#{@title}"}
        <:subtitle>
          A ghosted version is skipped by every deployment. Removing it here lets the engine
          offer it again on the next check.
        </:subtitle>
      </.header>

      <%= if @ghosted_list == [] do %>
        <div class="mt-4 rounded-lg border border-base-300 bg-base-200 px-4 py-6 text-center">
          <span class="text-sm text-base-content/60 italic">No ghosted versions</span>
        </div>
      <% else %>
        <div class="mt-4 flex items-center justify-between">
          <span class="text-sm text-base-content/70">
            {length(@ghosted_list)} ghosted {if length(@ghosted_list) == 1,
              do: "version",
              else: "versions"}
          </span>
          <button
            id="ghosted-clear-all"
            class="btn btn-sm btn-error"
            phx-click="ghosted-clear-request"
          >
            Clear All
          </button>
        </div>

        <div class="relative mt-2 overflow-x-auto overflow-y-auto shadow-md sm:rounded-lg max-h-96">
          <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
            <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-400 dark:text-gray-200 sticky top-0 z-10">
              <tr>
                <th scope="col" class="px-6 py-1">
                  Version
                </th>
                <th scope="col" class="px-6 py-1">
                  Sname
                </th>
                <th scope="col" class="px-6 py-1">
                  Deploy Type
                </th>
                <th scope="col" class="px-6 py-1">
                  Date
                </th>
                <th scope="col" class="px-6 py-1">
                  Action
                </th>
              </tr>
            </thead>
            <tbody>
              <%= for version <- @ghosted_list do %>
                <tr class="bg-white border-b dark:bg-gray-800 dark:border-gray-700">
                  <th
                    scope="row"
                    class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
                  >
                    {version.version}
                  </th>
                  <td class="px-6 py-2">
                    {version.sname}
                  </td>
                  <td class="px-3 py-2">
                    {version.deployment}
                  </td>
                  <td class="px-6 py-2">
                    {format_date(version.inserted_at)}
                  </td>
                  <td class="px-6 py-2">
                    <button
                      id={"ghosted-remove-#{version_id(version.version)}"}
                      class="btn btn-xs btn-outline btn-error"
                      phx-click="ghosted-remove-request"
                      phx-value-version={version.version}
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(%{name: name} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:ghosted_list, Status.ghosted_version_list(name))

    {:ok, socket}
  end

  # The version becomes part of a DOM id, and a dot there would be read as a class selector
  defp version_id(version), do: String.replace(version, ".", "-")

  defp format_date(nil), do: "-/-"
  defp format_date(inserted_at), do: NaiveDateTime.to_string(inserted_at)
end
