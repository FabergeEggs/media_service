defmodule MediaServiceWeb.API.V1.CompatController do
  # TODO(remove-compat-shim)

  use MediaServiceWeb, :controller

  alias MediaService.Assets
  alias MediaServiceWeb.API.V1.AssetJSON

  action_fallback MediaServiceWeb.API.V1.FallbackController

  def delete_avatar(conn, %{"id" => id}) do
    with {:ok, _} <- Assets.soft_delete(id) do
      send_resp(conn, :no_content, "")
    end
  end

  def show_attached(conn, %{"id" => id}) do
    with {:ok, result} <- Assets.fetch_with_download_url(id) do
      json(conn, AssetJSON.show(result))
    end
  end

  def delete_attached(conn, %{"id" => id}) do
    with {:ok, _} <- Assets.soft_delete(id) do
      send_resp(conn, :no_content, "")
    end
  end

  # TODO(owner-id)
  def create_attached(conn, params) do
    caller = conn.assigns[:caller_service] || "unknown"

    with {:ok, %Plug.Upload{} = upload} <- fetch_upload(params),
         {:ok, owner_id} <- fetch_param(params, "owner_id"),
         owner_kind = Map.get(params, "owner_kind", "response"),
         {:ok, size} <- file_size(upload.path),
         {:ok, %{asset: asset, upload: presign}} <-
           Assets.create_upload(%{
             owner_kind: owner_kind,
             owner_id: owner_id,
             filename: upload.filename || "untitled",
             content_type: upload.content_type || "application/octet-stream",
             size_bytes: size,
             created_by_service: caller
           }),
         :ok <- put_to_s3(presign, upload.path),
         {:ok, confirmed} <- Assets.confirm_upload(asset.id) do
      conn
      |> put_status(:created)
      |> json(%{asset: AssetJSON.base(confirmed)})
    end
  end

  defp fetch_upload(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp fetch_upload(_), do: {:error, {:missing_params, ["file"]}}

  defp fetch_param(params, key) do
    case Map.get(params, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:missing_params, [key]}}
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, reason}
    end
  end

  # TODO(streaming-upload)
  defp put_to_s3(%{url: url, headers: headers}, file_path) do
    body = File.read!(file_path)

    case Req.put(url, body: body, headers: headers, retry: false) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:s3_put_failed, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
