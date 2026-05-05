defmodule MediaServiceWeb.API.V1.MeControllerTest do
  use MediaServiceWeb.ConnCase, async: false

  import Mox

  alias MediaService.Assets
  alias MediaService.Storage.Stub

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Stub.install_default_stubs()
    :ok
  end

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

  describe "GET /api/v1/me/assets/:id" do
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

  describe "GET /api/v1/me/assets (index)" do
    test "lists only ready assets owned by the user" do
      user_id = Ecto.UUID.generate()
      ready = create_owned_asset(user_id)
      _pending = create_owned_asset(user_id, ready: false)
      _other_user = create_owned_asset(Ecto.UUID.generate())

      resp = user_conn(user_id) |> get("/api/v1/me/assets") |> json_response(200)

      assert [item] = resp["items"]
      assert item["id"] == ready.id
      assert item["kind"] == "image"
      refute Map.has_key?(item, "download_url")
    end

    test "401 without X-User-Id" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> get("/api/v1/me/assets")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/me/uploads" do
    test "creates pending asset and returns presigned PUT URL" do
      user_id = Ecto.UUID.generate()

      resp =
        user_conn(user_id)
        |> post("/api/v1/me/uploads", %{
          "filename" => "photo.jpg",
          "content_type" => "image/jpeg",
          "size_bytes" => 12_345
        })
        |> json_response(201)

      assert resp["asset"]["status"] == "pending"
      assert resp["asset"]["owner_kind"] == "user"
      assert resp["asset"]["owner_id"] == user_id
      assert resp["upload"]["url"] =~ "sig=put"
    end

    test "forces owner_id = X-User-Id even if client tries to spoof" do
      user_id = Ecto.UUID.generate()
      stranger = Ecto.UUID.generate()

      resp =
        user_conn(user_id)
        |> post("/api/v1/me/uploads", %{
          "filename" => "x.jpg",
          "content_type" => "image/jpeg",
          "size_bytes" => 1,
          "owner_id" => stranger,
          "owner_kind" => "project"
        })
        |> json_response(201)

      assert resp["asset"]["owner_id"] == user_id
      assert resp["asset"]["owner_kind"] == "user"
    end

    test "400 when required fields are missing" do
      resp =
        user_conn(Ecto.UUID.generate())
        |> post("/api/v1/me/uploads", %{"filename" => "x.jpg"})
        |> json_response(400)

      assert resp["error"] == "missing_params"
    end

    test "401 without X-User-Id" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> post("/api/v1/me/uploads", %{
          "filename" => "x.jpg",
          "content_type" => "image/jpeg",
          "size_bytes" => 1
        })

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/me/uploads/:id/complete" do
    test "owner can complete upload" do
      user_id = Ecto.UUID.generate()
      asset = create_owned_asset(user_id, ready: false)

      expect(Stub.mock(), :head_object, fn _ ->
        {:ok,
         %{content_length: 123, content_type: "image/jpeg", etag: "x", last_modified: nil}}
      end)

      resp =
        user_conn(user_id)
        |> post("/api/v1/me/uploads/#{asset.id}/complete", %{})
        |> json_response(200)

      assert resp["asset"]["status"] == "scanning"
    end

    test "stranger gets 404" do
      owner = Ecto.UUID.generate()
      asset = create_owned_asset(owner, ready: false)

      resp =
        user_conn(Ecto.UUID.generate())
        |> post("/api/v1/me/uploads/#{asset.id}/complete", %{})
        |> json_response(404)

      assert resp["error"] == "not_found"
    end

    test "404 for unknown id" do
      resp =
        user_conn(Ecto.UUID.generate())
        |> post("/api/v1/me/uploads/#{Ecto.UUID.generate()}/complete", %{})
        |> json_response(404)

      assert resp["error"] == "not_found"
    end
  end

  describe "DELETE /api/v1/me/assets/:id" do
    test "owner can delete and asset becomes :deleted" do
      user_id = Ecto.UUID.generate()
      asset = create_owned_asset(user_id)

      expect(Stub.mock(), :delete_object, fn _ -> :ok end)

      conn = user_conn(user_id) |> delete("/api/v1/me/assets/#{asset.id}")
      assert conn.status == 204

      {:ok, reloaded} = Assets.fetch(asset.id)
      assert reloaded.status == "deleted"
    end

    test "stranger gets 404 and asset is untouched" do
      owner = Ecto.UUID.generate()
      asset = create_owned_asset(owner)

      conn = user_conn(Ecto.UUID.generate()) |> delete("/api/v1/me/assets/#{asset.id}")
      assert json_response(conn, 404)

      {:ok, reloaded} = Assets.fetch(asset.id)
      assert reloaded.status == "ready"
    end

    test "401 without X-User-Id" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> delete("/api/v1/me/assets/#{Ecto.UUID.generate()}")

      assert json_response(conn, 401)
    end
  end
end
