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
            <div class="text-center mb-4">
              <div class="mx-auto mb-3 w-12 h-12 bg-primary/10 rounded-lg flex items-center justify-center">
                <img src="/images/logo.svg" alt="DeployEx" class="w-7 h-7" />
              </div>
              <p class="text-2xl font-semibold leading-5 text-slate-900">
                DeployEx
              </p>
              <p class="mt-2 text-sm leading-4 text-slate-600">
                Sign in to the management console
              </p>
            </div>

            <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
              <%!-- Naming the credential fields explicitly keeps password managers on this
                    form instead of guessing at any other text plus password pair in the UI --%>
              <.input
                field={@form[:username]}
                type="text"
                placeholder="Username"
                autocomplete="username"
                required
              />
              <.input
                field={@form[:password]}
                type="password"
                placeholder="Password"
                autocomplete="current-password"
                required
              />

              <:actions>
                <.button phx-disable-with="Signing in..." class="w-full">
                  Sign in <span aria-hidden="true">→</span>
                </.button>
              </:actions>
            </.simple_form>

            <div :if={@oauth_configured?} class="mt-4">
              <div class="divider text-xs text-slate-500">or</div>
              <a href={~p"/auth/github"} class="btn btn-neutral w-full gap-2">
                <svg viewBox="0 0 16 16" class="w-5 h-5 fill-current" aria-hidden="true">
                  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
                </svg>
                Sign in with GitHub
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> assign(form: form)
      |> assign(oauth_configured?: DeployexWeb.OAuth.Config.configured?())

    {:ok, socket, temporary_assigns: [form: form]}
  end
end
