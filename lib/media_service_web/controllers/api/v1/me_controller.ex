defmodule MediaServiceWeb.API.V1.MeController do
  use MediaServiceWeb, :controller

  alias MediaService.Assets
  alias MediaServiceWeb.API.V1.AssetJSON

  action_fallback MediaServiceWeb.API.V1.FallbackController

  @upload_required ~w(filename content_type size_bytes)
  @max_upload_bytes 104_857_600

  def show(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    with {:ok, result} <- Assets.fetch_for_user(id, user_id) do
      json(conn, AssetJSON.user_show(result))
    end
  end

  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    assets = Assets.list_for_owner("user", user_id)
    json(conn, %{items: Enum.map(assets, &AssetJSON.user_index_item/1)})
  end

  def create_upload(conn, params) do
    user_id = conn.assigns.current_user.id

    with :ok <- ensure_required(params, @upload_required),
         {:ok, size} <- coerce_size(params["size_bytes"]),
         {:ok, result} <-
           Assets.create_upload(%{
             owner_kind: "user",
             owner_id: user_id,
             filename: to_string(params["filename"]),
             content_type: to_string(params["content_type"]),
             size_bytes: size,
             visibility: Map.get(params, "visibility", "owner_only"),
             metadata: Map.get(params, "metadata", %{}),
             created_by_service: "frontend"
           }) do
      proxy_url = proxy_upload_url(result.asset.id)
      modified_upload = Map.put(result.upload, :url, proxy_url)

      conn
      |> put_status(:created)
      |> json(AssetJSON.upload_created(%{result | upload: modified_upload}))
    end
  end

  def upload_data(conn, %{"id" => id}) do
    storage = MediaService.Storage.S3
    content_type =
      conn |> get_req_header("content-type") |> List.first() || "application/octet-stream"

    with {:ok, asset} <- Assets.fetch_pending(id),
         {:ok, body, conn} <- read_body(conn, length: @max_upload_bytes),
         :ok <- storage.put_object(asset.object_key, body, content_type: content_type) do
      send_resp(conn, 204, "")
    end
  end

  def complete_upload(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    with {:ok, asset} <- Assets.confirm_upload_for_user(id, user_id) do
      json(conn, %{asset: AssetJSON.base(asset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    with {:ok, _} <- Assets.soft_delete_for_user(id, user_id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp proxy_upload_url(asset_id) do
    base =
      Application.get_env(:media_service, :public_gateway_url, "http://localhost:8080")

    "#{base}/api/v1/media/me/uploads/#{asset_id}/data"
  end

  defp ensure_required(params, required) do
    case Enum.reject(required, &Map.has_key?(params, &1)) do
      [] -> :ok
      missing -> {:error, {:missing_params, missing}}
    end
  end

  defp coerce_size(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp coerce_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_size}
    end
  end

  defp coerce_size(_), do: {:error, :invalid_size}
end
