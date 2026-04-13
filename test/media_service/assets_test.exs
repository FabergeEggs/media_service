defmodule MediaService.AssetsTest do
  use MediaService.DataCase, async: false

  import Mox

  alias MediaService.Assets
  alias MediaService.Storage.Stub

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Stub.install_default_stubs()
    :ok
  end

  @base_attrs %{
    owner_kind: "project",
    owner_id: Ecto.UUID.generate(),
    filename: "photo.jpg",
    content_type: "image/jpeg",
    size_bytes: 123,
    created_by_service: "project-service"
  }

  describe "create_upload/1" do
    test "inserts pending asset and returns presigned URL" do
      assert {:ok, %{asset: asset, upload: upload}} = Assets.create_upload(@base_attrs)

      assert asset.status == "pending"
      assert asset.bucket == Stub.bucket()
      assert asset.created_by_service == "project-service"
      assert String.contains?(asset.object_key, asset.id)

      assert upload.url =~ asset.object_key
      assert upload.expires_in == 600
    end

    test "rejects unknown owner_kind" do
      attrs = %{@base_attrs | owner_kind: "alien"}
      assert {:error, %Ecto.Changeset{}} = Assets.create_upload(attrs)
    end

    test "rejects non-positive size" do
      attrs = %{@base_attrs | size_bytes: 0}
      assert {:error, %Ecto.Changeset{}} = Assets.create_upload(attrs)
    end
  end

  describe "confirm_upload/1" do
    test "transitions pending → ready when head_object confirms size" do
      {:ok, %{asset: asset}} = Assets.create_upload(@base_attrs)

      expect(Stub.mock(), :head_object, fn _key ->
        {:ok,
         %{
           content_length: @base_attrs.size_bytes,
           content_type: "image/jpeg",
           etag: "\"x\"",
           last_modified: nil
         }}
      end)

      assert {:ok, confirmed} = Assets.confirm_upload(asset.id)
      assert confirmed.status == "ready"
    end

    test "reports size mismatch without changing status" do
      {:ok, %{asset: asset}} = Assets.create_upload(@base_attrs)

      expect(Stub.mock(), :head_object, fn _key ->
        {:ok, %{content_length: 1, content_type: "image/jpeg", etag: nil, last_modified: nil}}
      end)

      assert {:error, {:size_mismatch, %{declared: 123, actual: 1}}} =
               Assets.confirm_upload(asset.id)

      assert {:ok, reloaded} = Assets.fetch(asset.id)
      assert reloaded.status == "pending"
    end

    test "reports not_found for unknown id" do
      assert {:error, :not_found} = Assets.confirm_upload(Ecto.UUID.generate())
    end
  end

  describe "fetch_with_download_url/1" do
    test "returns nil download for pending asset" do
      {:ok, %{asset: asset}} = Assets.create_upload(@base_attrs)

      assert {:ok, %{asset: ^asset, download: nil}} =
               Assets.fetch_with_download_url(asset.id)
    end

    test "returns signed URL once asset is ready" do
      {:ok, %{asset: asset}} = Assets.create_upload(@base_attrs)

      expect(Stub.mock(), :head_object, fn _ ->
        {:ok, %{content_length: 123, content_type: "image/jpeg", etag: nil, last_modified: nil}}
      end)

      {:ok, _} = Assets.confirm_upload(asset.id)

      assert {:ok, %{download: %{url: url}}} = Assets.fetch_with_download_url(asset.id)
      assert url =~ "sig=get"
    end
  end

  describe "soft_delete/1" do
    test "is idempotent" do
      {:ok, %{asset: asset}} = Assets.create_upload(@base_attrs)

      assert {:ok, deleted} = Assets.soft_delete(asset.id)
      assert deleted.status == "deleted"
      assert deleted.deleted_at != nil

      assert {:ok, still_deleted} = Assets.soft_delete(asset.id)
      assert still_deleted.status == "deleted"
    end
  end

  describe "list_for_owner/2" do
    test "only ready assets of given owner" do
      owner_id = Ecto.UUID.generate()

      {:ok, %{asset: a}} =
        Assets.create_upload(%{@base_attrs | owner_id: owner_id})

      {:ok, %{asset: _b}} =
        Assets.create_upload(%{@base_attrs | owner_id: owner_id, filename: "other.jpg"})

      # Mark the first one ready.
      expect(Stub.mock(), :head_object, fn _ ->
        {:ok, %{content_length: 123, content_type: "image/jpeg", etag: nil, last_modified: nil}}
      end)

      {:ok, _} = Assets.confirm_upload(a.id)

      assert [ready] = Assets.list_for_owner("project", owner_id)
      assert ready.id == a.id
    end
  end
end
