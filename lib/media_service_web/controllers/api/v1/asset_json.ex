defmodule MediaServiceWeb.API.V1.AssetJSON do
  @moduledoc """
  JSON views for asset-related endpoints. Kept as a module of pure functions
  so controllers stay thin.
  """

  alias MediaService.Media.Asset

  @spec upload_created(%{asset: Asset.t(), upload: map()}) :: map()
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

  @spec show(%{asset: Asset.t(), download: map() | nil}) :: map()
  def show(%{asset: asset, download: nil}) do
    %{asset: base(asset), download: nil}
  end

  def show(%{asset: asset, download: presign}) do
    %{
      asset: base(asset),
      download: %{
        url: presign.url,
        expires_in: presign.expires_in
      }
    }
  end

  @spec list([Asset.t()]) :: map()
  def list(assets) when is_list(assets) do
    %{assets: Enum.map(assets, &base/1)}
  end

  @spec base(Asset.t()) :: map()
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
