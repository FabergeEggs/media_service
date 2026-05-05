defmodule MediaServiceWeb.API.V1.CompatControllerTest do
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

  defp ready_asset(opts \\ []) do
    attrs = %{
      owner_kind: Keyword.get(opts, :owner_kind, "response"),
      owner_id: Keyword.get(opts, :owner_id, Ecto.UUID.generate()),
      filename: "x.jpg",
      content_type: "image/jpeg",
      size_bytes: 123,
      created_by_service: "response-service"
    }

    {:ok, %{asset: a}} = Assets.create_upload(attrs)
    force_ready(a)
  end

  describe "DELETE /avatar/:id (COMPAT profile_service)" do
    test "soft-deletes the asset", %{conn: conn} do
      asset = ready_asset(owner_kind: "user")

      expect(Stub.mock(), :delete_object, fn _ -> :ok end)

      conn = delete(conn, "/avatar/#{asset.id}")
      assert conn.status == 204

      {:ok, reloaded} = Assets.fetch(asset.id)
      assert reloaded.status == "deleted"
    end

    test "401 without S2S token" do
      conn = build_conn() |> delete("/avatar/#{Ecto.UUID.generate()}")
      assert json_response(conn, 401)
    end
  end

  describe "GET /attached_files/:id (COMPAT response_service)" do
    test "returns asset with download URL", %{conn: conn} do
      asset = ready_asset()
      resp = conn |> get("/attached_files/#{asset.id}") |> json_response(200)

      assert resp["asset"]["id"] == asset.id
      assert resp["download"]["url"] =~ "sig=get"
    end

    test "404 for unknown id", %{conn: conn} do
      assert conn |> get("/attached_files/#{Ecto.UUID.generate()}") |> json_response(404)
    end
  end

  describe "DELETE /attached_files/:id (COMPAT response_service)" do
    test "soft-deletes", %{conn: conn} do
      asset = ready_asset()

      expect(Stub.mock(), :delete_object, fn _ -> :ok end)

      conn = delete(conn, "/attached_files/#{asset.id}")
      assert conn.status == 204
    end
  end

  describe "POST /attached_files (COMPAT response_service)" do
    test "400 when file part is missing", %{conn: conn} do
      resp =
        conn
        |> post("/attached_files", %{"owner_id" => Ecto.UUID.generate()})
        |> json_response(400)

      assert resp["error"] == "missing_params"
      assert "file" in resp["fields"]
    end

    test "400 when owner_id is missing", %{conn: conn} do
      upload = %Plug.Upload{
        path: write_temp("hello"),
        filename: "x.txt",
        content_type: "text/plain"
      }

      resp =
        conn
        |> post("/attached_files", %{"file" => upload})
        |> json_response(400)

      assert resp["error"] == "missing_params"
      assert "owner_id" in resp["fields"]
    end

    # TODO(testing): full happy-path requires stubbing the synchronous PUT
    # to S3 via Req.Test. Smoke-test through dev MinIO until done.
    @tag :skip
    test "happy path uploads, syncs to S3 and confirms"
  end

  defp write_temp(body) do
    path = Path.join(System.tmp_dir!(), "compat_#{System.unique_integer([:positive])}")
    File.write!(path, body)
    path
  end
end
