defmodule MediaService.Repo do
  use Ecto.Repo,
    otp_app: :media_service,
    adapter: Ecto.Adapters.Postgres
end
