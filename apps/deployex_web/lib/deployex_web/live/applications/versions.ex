defmodule DeployexWeb.ApplicationsLive.Versions do
  use DeployexWeb, :live_component

  require Logger

  alias Deployer.Status

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {"#{@title}"}
      </.header>

      <div class="relative overflow-x-auto overflow-y-auto shadow-md sm:rounded-lg max-h-96">
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
            </tr>
          </thead>
          <tbody>
            <%= for version <- @version_list do %>
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
                  {"#{NaiveDateTime.to_string(version.inserted_at)}"}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    sname = assigns.id

    version_list =
      if sname == "deployex" do
        Status.history_version_list()
      else
        Status.history_version_list(sname)
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:version_list, version_list)

    {:ok, socket}
  end
end
