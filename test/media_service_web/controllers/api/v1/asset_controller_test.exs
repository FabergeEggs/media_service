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

  describe "GET /api/v1/me/assets/:id" do
    # The fixture above stamps `x-service-token`. For user-API tests
    # we rebuild a clean conn and inject X-User-* instead.
    defp user_conn(user_id) do
      Phoenix.ConnTest.build_conn()
      |> put_req_header("x-user-id", user_id)
      |> put_req_header("x-username", "alice")
    end

    defp create_owned_asset(user_id, opts \\ []) do
      attrs = %{
        owner_kind: "user",
        owner_id: user_id,
        filename: "selfie.jpg",
        content_type: "image/jpeg",
        size_bytes: 123,
        created_by_service: "profile-service",
        visibility: Keyword.get(opts, :visibility, "owner_only")
      }

      {:ok, %{asset: a}} = Assets.create_upload(attrs)
      if Keyword.get(opts, :ready, true), do: force_ready(a), else: a
    end

    test "401 without X-User-Id" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> get("/api/v1/me/assets/#{Ecto.UUID.generate()}")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "owner gets metadata + download_url + kind" do
      user_id = Ecto.UUID.generate()
      asset = create_owned_asset(user_id)

      resp = user_conn(user_id) |> get("/api/v1/me/assets/#{asset.id}") |> json_response(200)

      assert resp["id"] == asset.id
      assert resp["status"] == "ready"
      assert resp["kind"] == "image"
      assert resp["mime"] == "image/jpeg"
      assert resp["size_bytes"] == 123
      assert resp["download_url"] =~ "sig=get"
      assert resp["preview_url"] == nil
    end

    test "stranger gets 404 on someone else's owner_only asset" do
      other = Ecto.UUID.generate()
      asset = create_owned_asset(other)

      resp =
        user_conn(Ecto.UUID.generate())
        |> get("/api/v1/me/assets/#{asset.id}")
        |> json_response(404)

      assert resp["error"] == "not_found"
    end

    test "anyone gets a public asset" do
      owner = Ecto.UUID.generate()
      asset = create_owned_asset(owner, visibility: "public")

      resp =
        user_conn(Ecto.UUID.generate())
        |> get("/api/v1/me/assets/#{asset.id}")
        |> json_response(200)

      assert resp["id"] == asset.id
      assert resp["download_url"] =~ "sig=get"
    end

    test "pending owned asset returns nil download_url" do
      user_id = Ecto.UUID.generate()
      asset = create_owned_asset(user_id, ready: false)

      resp =
        user_conn(user_id)
        |> get("/api/v1/me/assets/#{asset.id}")
        |> json_response(200)

      assert resp["status"] == "pending"
      assert resp["download_url"] == nil
    end

    test "404 for unknown id" do
      resp =
        user_conn(Ecto.UUID.generate())
        |> get("/api/v1/me/assets/#{Ecto.UUID.generate()}")
        |> json_response(404)

      assert resp["error"] == "not_found"
    end
  end
end
