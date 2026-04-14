defmodule MediaServiceWeb.API.V1.UploadControllerTest do
  use MediaServiceWeb.ConnCase, async: false

  import Mox

  alias MediaService.Storage.Stub

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    Stub.install_default_stubs()

    conn = put_req_header(conn, "x-service-token", "test-project-token")
    {:ok, conn: conn}
  end

  @valid_body %{
    "owner_kind" => "project",
    "filename" => "photo.jpg",
    "content_type" => "image/jpeg",
    "size_bytes" => 123
  }

  describe "POST /api/v1/uploads" do
    test "401 without service token" do
      conn = post(build_conn(), "/api/v1/uploads", Map.put(@valid_body, "owner_id", "x"))
      assert conn.status == 401
    end

    test "400 on missing params", %{conn: conn} do
      conn = post(conn, "/api/v1/uploads", %{"owner_kind" => "project"})
      assert json_response(conn, 400)["error"] == "missing_params"
    end

    test "422 on invalid size", %{conn: conn} do
      body = Map.merge(@valid_body, %{"owner_id" => Ecto.UUID.generate(), "size_bytes" => 0})
      conn = post(conn, "/api/v1/uploads", body)
      assert json_response(conn, 422)
    end

    test "201 returns asset + upload presign", %{conn: conn} do
      body = Map.put(@valid_body, "owner_id", Ecto.UUID.generate())
      conn = post(conn, "/api/v1/uploads", body)
      resp = json_response(conn, 201)

      assert %{"asset" => asset, "upload" => upload} = resp
      assert asset["status"] == "pending"
      assert asset["created_by_service"] == "project-service"
      assert upload["url"] =~ asset["object_key"]
      assert upload["expires_in"] == 600
    end
  end

  describe "POST /api/v1/uploads/:id/complete" do
    test "200 and status=ready after head_object confirms size", %{conn: conn} do
      body = Map.put(@valid_body, "owner_id", Ecto.UUID.generate())
      create_resp = post(conn, "/api/v1/uploads", body) |> json_response(201)
      asset_id = create_resp["asset"]["id"]

      expect(Stub.mock(), :head_object, fn _ ->
        {:ok, %{content_length: 123, content_type: "image/jpeg", etag: nil, last_modified: nil}}
      end)

      resp =
        conn
        |> post("/api/v1/uploads/#{asset_id}/complete")
        |> json_response(200)

      assert resp["asset"]["status"] == "scanning"
    end

    test "422 on size mismatch", %{conn: conn} do
      body = Map.put(@valid_body, "owner_id", Ecto.UUID.generate())
      create_resp = post(conn, "/api/v1/uploads", body) |> json_response(201)
      asset_id = create_resp["asset"]["id"]

      expect(Stub.mock(), :head_object, fn _ ->
        {:ok, %{content_length: 1, content_type: "image/jpeg", etag: nil, last_modified: nil}}
      end)

      resp =
        conn
        |> post("/api/v1/uploads/#{asset_id}/complete")
        |> json_response(422)

      assert resp["error"] == "size_mismatch"
    end

    test "404 for unknown id", %{conn: conn} do
      conn = post(conn, "/api/v1/uploads/#{Ecto.UUID.generate()}/complete")
      assert json_response(conn, 404)["error"] == "not_found"
    end
  end
end
