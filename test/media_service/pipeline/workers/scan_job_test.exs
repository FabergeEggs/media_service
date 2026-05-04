defmodule MediaService.Pipeline.Workers.ScanJobTest do
  use MediaService.DataCase, async: false
  use Oban.Testing, repo: MediaService.Repo

  import Mox

  alias MediaService.Assets
  alias MediaService.Media.Asset
  alias MediaService.Pipeline.Workers.ScanJob
  alias MediaService.Storage.Stub

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Stub.install_default_stubs()
    :ok
  end

  defp scanning_asset(content_type \\ "image/jpeg", size_bytes \\ 123) do
    {:ok, %{asset: a}} =
      Assets.create_upload(%{
        owner_kind: "project",
        owner_id: Ecto.UUID.generate(),
        filename: "x.jpg",
        content_type: content_type,
        size_bytes: size_bytes,
        created_by_service: "test"
      })

    {:ok, scanning} = a |> Asset.status_changeset(:scanning) |> Repo.update()
    scanning
  end

  test "marks asset as ready when head matches declared mime/size" do
    asset = scanning_asset()

    expect(Stub.mock(), :head_object, fn _ ->
      {:ok, %{content_length: 123, content_type: "image/jpeg", etag: "x", last_modified: nil}}
    end)

    assert :ok = perform_job(ScanJob, %{"asset_id" => asset.id})

    reloaded = Repo.get!(Asset, asset.id)
    assert reloaded.status == "ready"
    assert reloaded.detected_mime == "image/jpeg"
    assert reloaded.scanned_at
  end

  test "rejects when content_type differs from declared_mime" do
    asset = scanning_asset()

    expect(Stub.mock(), :head_object, fn _ ->
      {:ok,
       %{
         content_length: 123,
         content_type: "application/x-msdownload",
         etag: "x",
         last_modified: nil
       }}
    end)

    assert :ok = perform_job(ScanJob, %{"asset_id" => asset.id})

    reloaded = Repo.get!(Asset, asset.id)
    assert reloaded.status == "rejected"
    assert reloaded.rejection_reason == "mime_mismatch"
  end

  test "rejects when content_length differs from declared size" do
    asset = scanning_asset()

    expect(Stub.mock(), :head_object, fn _ ->
      {:ok,
       %{content_length: 999_999, content_type: "image/jpeg", etag: "x", last_modified: nil}}
    end)

    assert :ok = perform_job(ScanJob, %{"asset_id" => asset.id})

    reloaded = Repo.get!(Asset, asset.id)
    assert reloaded.status == "rejected"
    assert reloaded.rejection_reason == "too_large"
  end

  test "no-op when asset is missing (idempotent retry safety)" do
    assert {:error, :not_found} = perform_job(ScanJob, %{"asset_id" => Ecto.UUID.generate()})
  end

  test "no-op when asset already :ready (duplicate enqueue)" do
    asset = scanning_asset()
    {:ok, _ready} = asset |> Asset.status_changeset(:ready) |> Repo.update()

    assert {:ok, :already_done} = perform_job(ScanJob, %{"asset_id" => asset.id})
  end

  test "returns error so Oban retries when storage is down" do
    asset = scanning_asset()

    expect(Stub.mock(), :head_object, fn _ -> {:error, :timeout} end)

    assert {:error, :timeout} = perform_job(ScanJob, %{"asset_id" => asset.id})

    reloaded = Repo.get!(Asset, asset.id)
    assert reloaded.status == "scanning"
  end
end
