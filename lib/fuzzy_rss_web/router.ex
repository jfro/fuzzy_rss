defmodule FuzzyRssWeb.Router do
  use FuzzyRssWeb, :router

  import FuzzyRssWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FuzzyRssWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :ueberauth do
    plug Ueberauth
  end

  scope "/", FuzzyRssWeb do
    pipe_through :browser

    get "/", PageController, :redirect_to_app
  end

  # Other scopes may use custom stacks.
  # scope "/api", FuzzyRssWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fuzzy_rss, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FuzzyRssWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", FuzzyRssWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", FuzzyRssWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  ## Application routes

  scope "/app", FuzzyRssWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{FuzzyRssWeb.UserAuth, :ensure_authenticated}] do
      live "/", ReaderLive.Index, :index
      live "/folder/:folder_id", ReaderLive.Index, :folder
      live "/feed/:feed_id", ReaderLive.Index, :feed
      live "/starred", ReaderLive.Index, :starred

      live "/feeds", ReaderLive.Index, :feeds
      live "/feeds/new", ReaderLive.Index, :feeds_new
      live "/feeds/discover", ReaderLive.Index, :feeds_discover

      live "/folders", ReaderLive.Index, :folders

      live "/settings", ReaderLive.Index, :settings
      live "/settings/import-export", ReaderLive.Index, :settings_import_export
      live "/account-settings", ReaderLive.Index, :account_settings
    end
  end

  scope "/", FuzzyRssWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # OIDC authentication routes (optional, can be disabled)
  if Application.compile_env(:fuzzy_rss, [:oidc_enabled], false) do
    scope "/auth", FuzzyRssWeb do
      pipe_through [:browser, :ueberauth]

      get "/:provider", AuthController, :request
      get "/:provider/callback", AuthController, :callback
      post "/:provider/callback", AuthController, :callback
    end
  end
end
