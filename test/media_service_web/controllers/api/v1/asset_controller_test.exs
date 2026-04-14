defmodule MediaServiceWeb.API.V1.AssetControllerTest do
  use MediaServiceWeb.ConnCase, async: false

  import Mox

  alias MediaService.Assets
  alias MediaService.Storage.Stub

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    Stub.install_default_stubs()
    conn = put_req_header(conn, "x-service-token", "test-project-token")
    {:ok, conn: conn}
  end

  defp create_asset(status) do
    attrs = %{
      owner_kind: "project",
      owner_id: Ecto.UUID.generate(),
      filename: "x.jpg",
      content_type: "image/jpeg",
      size_bytes: 123,
      created_by_service: "project-service"
    }

    {:ok, %{asset: asset}} = Assets.create_upload(attrs)

    case status do
      :pending -> asset
      :ready -> force_ready(asset)
    end
  end

  describe "GET /api/v1/assets/:id" do
    test "returns metadata + nil download when pending", %{conn: conn} do
      asset = create_asset(:pending)
      resp = conn |> get("/api/v1/assets/#{asset.id}") |> json_response(200)

      assert resp["asset"]["status"] == "pending"
      assert resp["download"] == nil
    end

    test "returns signed URL when ready", %{conn: conn} do
      asset = create_asset(:ready)
      resp = conn |> get("/api/v1/assets/#{asset.id}") |> json_response(200)

      assert resp["asset"]["status"] == "ready"
      assert resp["download"]["url"] =~ "sig=get"
    end

    test "404 for unknown id", %{conn: conn} do
      conn = get(conn, "/api/v1/assets/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/assets (index)" do
    test "filters by owner and returns only ready", %{conn: conn} do
      owner_id = Ecto.UUID.generate()

      {:ok, %{asset: a}} =
        Assets.create_upload(%{
          owner_kind: "project",
          owner_id: owner_id,
          filename: "a.jpg",
          content_type: "image/jpeg",
          size_bytes: 123,
          created_by_service: "project-service"
        })

      ready = force_ready(a)

      {:ok, _} =
        Assets.create_upload(%{
          owner_kind: "project",
          owner_id: owner_id,
          filename: "pending.jpg",
          content_type: "image/jpeg",
          size_bytes: 123,
          created_by_service: "project-service"
        })

      resp =
        conn
        |> get("/api/v1/assets", owner_kind: "project", owner_id: owner_id)
        |> json_response(200)

      assert [a] = resp["assets"]
      assert a["id"] == ready.id
    end

    test "400 without owner params", %{conn: conn} do
      assert conn |> get("/api/v1/assets") |> json_response(400)
    end
  end

  describe "DELETE /api/v1/assets/:id" do
    test "204 and asset is marked deleted", %{conn: conn} do
      asset = create_asset(:pending)

      expect(Stub.mock(), :delete_object, fn _ -> :ok end)

      conn = delete(conn, "/api/v1/assets/#{asset.id}")
      assert conn.status == 204

      {:ok, reloaded} = Assets.fetch(asset.id)
      assert reloaded.status == "deleted"
    end
  end
end
