defmodule MediaServiceWeb.API.V1.AssetController do
  use MediaServiceWeb, :controller

  alias MediaService.Assets
  alias MediaServiceWeb.API.V1.AssetJSON

  action_fallback MediaServiceWeb.API.V1.FallbackController

  def show(conn, %{"id" => id}) do
    with {:ok, result} <- Assets.fetch_with_download_url(id) do
      json(conn, AssetJSON.show(result))
    end
  end

  def user_show(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    with {:ok, result} <- Assets.fetch_for_user(id, user_id) do
      json(conn, AssetJSON.user_show(result))
    end
  end

  def index(conn, %{"owner_kind" => owner_kind, "owner_id" => owner_id}) do
    assets = Assets.list_for_owner(to_string(owner_kind), to_string(owner_id))
    json(conn, AssetJSON.list(assets))
  end

  def index(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "owner_kind and owner_id query params are required"})
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _asset} <- Assets.soft_delete(id) do
      send_resp(conn, :no_content, "")
    end
  end
end
