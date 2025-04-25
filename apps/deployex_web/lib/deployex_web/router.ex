defmodule DeployexWeb.Router do
  use DeployexWeb, :router

  import DeployexWeb.UserAuth

  import Observer.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DeployexWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self' 'unsafe-inline' opshealth.net *.opshealth.net data:;"
    }

    plug :fetch_current_user
  end

  scope "/", DeployexWeb do
    pipe_through :browser

    get "/about", PageController, :show
  end

  ## Authentication routes

  scope "/", DeployexWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{DeployexWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/log_in", UserLoginLive, :new
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", DeployexWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{DeployexWeb.UserAuth, :ensure_authenticated}] do
      live "/", ApplicationsLive, :index
      live "/terminal", TerminalLive, :index
      live "/logs/live", LogsLive, :index
      live "/logs/history", HistoryLive, :index
      live "/embedded-observer", ObserverLive, :index
      live "/applications", ApplicationsLive, :index
      live "/applications/:instance/logs/stdout", ApplicationsLive, :logs_stdout
      live "/applications/:instance/logs/stderr", ApplicationsLive, :logs_stderr
      live "/applications/:instance/terminal", ApplicationsLive, :terminal
      live "/applications/:instance/versions", ApplicationsLive, :versions
      live "/applications/:instance/restart", ApplicationsLive, :restart
    end

    observer_dashboard("/observer")
  end

  # Other scopes may use custom stacks.
  # scope "/api", DeployexWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:deployex_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DeployexWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
