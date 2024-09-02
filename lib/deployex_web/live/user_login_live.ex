defmodule DeployexWeb.UserLoginLive do
  use DeployexWeb, :live_view

  def render(assigns) do
    ~H"""
    <div
      id="login-popup"
      tabindex="-1"
      class="bg-black/50 overflow-y-auto overflow-x-hidden fixed top-0 right-0 left-0 z-50 h-full items-center justify-center flex"
    >
      <div class="relative p-4 w-full max-w-md h-full md:h-auto">
        <div class="relative bg-white rounded-lg shadow">
          <div class="p-5">
            <h3 class="text-2xl mb-0.5 font-medium"></h3>
            <p class="mb-4 text-sm font-normal text-gray-800"></p>

            <div class="text-center">
              <p class="mb-3 text-2xl font-semibold leading-5 text-slate-900">
                Login to your account
              </p>
              <p class="mt-2 text-sm leading-4 text-slate-600">
                You must be logged in to perform this action.
              </p>
            </div>

            <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
              <.input field={@form[:username]} type="text" placeholder="Username" required />
              <.input
                field={@form[:password]}
                type="password"
                placeholder="current-password"
                required
              />

              <:actions>
                <.button phx-disable-with="Signing in..." class="w-full">
                  Sign in <span aria-hidden="true">→</span>
                </.button>
              </:actions>
            </.simple_form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
