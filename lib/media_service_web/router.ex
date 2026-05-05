defmodule MediaServiceWeb.Router do
  use MediaServiceWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :s2s_api do
    plug :accepts, ["json"]
    plug MediaServiceWeb.Plugs.S2SAuth
  end

  pipeline :user_api do
    plug :accepts, ["json"]
    plug MediaServiceWeb.Plugs.UserContext
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

  # Client-facing API. Frontend hits this through the gateway, which
  # injects X-User-* after JWT validation. owner_kind/owner_id are
  # forced to "user" + X-User-Id — frontend cannot upload for others.
  scope "/api/v1/me", MediaServiceWeb.API.V1 do
    pipe_through :user_api

    get "/assets", MeController, :index
    get "/assets/:id", MeController, :show
    delete "/assets/:id", MeController, :delete

    post "/uploads", MeController, :create_upload
    post "/uploads/:id/complete", MeController, :complete_upload
  end

  # COMPAT: legacy paths used by profile_service and response_service.
  # See CompatController moduledoc — remove once those services migrate.
  scope "/", MediaServiceWeb.API.V1 do
    pipe_through :s2s_api

    delete "/avatar/:id", CompatController, :delete_avatar

    post "/attached_files", CompatController, :create_attached
    get "/attached_files/:id", CompatController, :show_attached
    delete "/attached_files/:id", CompatController, :delete_attached
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
