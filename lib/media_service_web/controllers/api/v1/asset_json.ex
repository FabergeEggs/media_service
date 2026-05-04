defmodule MediaServiceWeb.API.V1.AssetJSON do
  alias MediaService.Media.Asset

  def upload_created(%{asset: asset, upload: presign}) do
    %{
      asset: base(asset),
      upload: %{
        url: presign.url,
        expires_in: presign.expires_in,
        headers: Map.new(presign.headers || [])
      }
    }
  end

  def show(%{asset: asset, download: nil}), do: %{asset: base(asset), download: nil}

  def show(%{asset: asset, download: presign}) do
    %{asset: base(asset), download: %{url: presign.url, expires_in: presign.expires_in}}
  end

  def list(assets) when is_list(assets), do: %{assets: Enum.map(assets, &base/1)}

  def user_show(%{asset: asset, download: download}) do
    mime = asset.detected_mime || asset.declared_mime

    %{
      id: asset.id,
      kind: kind_from_mime(mime),
      mime: mime,
      size_bytes: asset.size_bytes,
      status: asset.status,
      preview_url: nil,
      download_url: download && download.url,
      download_expires_in: download && download.expires_in
    }
  end

  defp kind_from_mime("image/" <> _), do: "image"
  defp kind_from_mime("video/" <> _), do: "video"
  defp kind_from_mime("audio/" <> _), do: "audio"
  defp kind_from_mime(_), do: "file"

  def base(%Asset{} = asset) do
    %{
      id: asset.id,
      owner_kind: asset.owner_kind,
      owner_id: asset.owner_id,
      bucket: asset.bucket,
      object_key: asset.object_key,
      original_filename: asset.original_filename,
      declared_mime: asset.declared_mime,
      size_bytes: asset.size_bytes,
      status: asset.status,
      visibility: asset.visibility,
      metadata: asset.metadata,
      created_by_service: asset.created_by_service,
      inserted_at: asset.inserted_at,
      updated_at: asset.updated_at,
      deleted_at: asset.deleted_at
    }
  end
end
