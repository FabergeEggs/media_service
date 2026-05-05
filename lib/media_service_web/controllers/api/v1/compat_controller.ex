defmodule MediaServiceWeb.API.V1.CompatController do
  @moduledoc """
  COMPAT shim for legacy paths used by other services.

  TODO(upstream): remove this controller once profile_service and
  response_service migrate to canonical /api/v1/uploads + /api/v1/assets/:id.
  See:
    - profile_service/src/infrastructure/clients/media_client.py
    - response_service/src/services/media_client.py
  """

  use MediaServiceWeb, :controller

  alias MediaService.Assets
  alias MediaServiceWeb.API.V1.AssetJSON

  action_fallback MediaServiceWeb.API.V1.FallbackController

  # COMPAT(profile_service): DELETE /avatar/:id
  def delete_avatar(conn, %{"id" => id}) do
    with {:ok, _} <- Assets.soft_delete(id) do
      send_resp(conn, :no_content, "")
    end
  end

  # COMPAT(response_service): GET /attached_files/:id
  def show_attached(conn, %{"id" => id}) do
    with {:ok, result} <- Assets.fetch_with_download_url(id) do
      json(conn, AssetJSON.show(result))
    end
  end

  # COMPAT(response_service): DELETE /attached_files/:id
  def delete_attached(conn, %{"id" => id}) do
    with {:ok, _} <- Assets.soft_delete(id) do
      send_resp(conn, :no_content, "")
    end
  end

  # COMPAT(response_service): POST /attached_files (multipart upload).
  # The legacy client pushes raw bytes via multipart instead of using the
  # presigned-PUT flow. We synchronously create_upload + PUT to S3 +
  # complete here so the client gets back a usable asset_id.
  #
  # TODO(upstream): response_service must include `owner_id` (the
  # response UUID) in the form payload — without it we have no way to
  # know who the file belongs to. Asks for {file, owner_id, [owner_kind]}.
  # When response_service adopts canonical /api/v1/uploads, drop this
  # action entirely.
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

  # TODO(streaming): for large files this loads the whole body into
  # memory. Replace with chunked Req streaming once response_service is
  # gone or the file-size cap is enforced upstream.
  defp put_to_s3(%{url: url, headers: headers}, file_path) do
    body = File.read!(file_path)

    case Req.put(url, body: body, headers: headers, retry: false) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:s3_put_failed, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
