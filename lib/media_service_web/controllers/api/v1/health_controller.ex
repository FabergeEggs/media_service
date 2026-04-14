defmodule MediaServiceWeb.API.V1.HealthController do
  use MediaServiceWeb, :controller

  alias MediaService.Repo

  def live(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    checks = %{db: db_ok?(), storage: storage_ok?()}

    if Enum.all?(checks, fn {_, v} -> v end) do
      json(conn, %{status: "ok", checks: checks})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "degraded", checks: checks})
    end
  end

  defp db_ok? do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp storage_ok? do
    storage = Application.get_env(:media_service, :storage_adapter, MediaService.Storage.S3)
    storage.bucket_reachable?()
  rescue
    _ -> false
  end
end
