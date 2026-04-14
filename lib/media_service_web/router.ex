defmodule MediaServiceWeb.Router do
  use MediaServiceWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :s2s_api do
    plug :accepts, ["json"]
    plug MediaServiceWeb.Plugs.S2SAuth
  end

  scope "/api/v1", MediaServiceWeb.API.V1 do
    pipe_through :api

    get "/health", HealthController, :live
    get "/health/ready", HealthController, :ready
  end

  scope "/api/v1", MediaServiceWeb.API.V1 do
    pipe_through :s2s_api

    post "/uploads", UploadController, :create
    post "/uploads/:id/complete", UploadController, :complete

    get "/assets", AssetController, :index
    get "/assets/:id", AssetController, :show
    delete "/assets/:id", AssetController, :delete
  end

  scope "/" do
    pipe_through :api

    get "/health", MediaServiceWeb.API.V1.HealthController, :live
    get "/health/ready", MediaServiceWeb.API.V1.HealthController, :ready
  end

  if Application.compile_env(:media_service, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: MediaServiceWeb.Telemetry
    end
  end
end
