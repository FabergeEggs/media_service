defmodule MediaServiceWeb.API.V1.HealthControllerTest do
  use MediaServiceWeb.ConnCase, async: false

  import Mox

  alias MediaService.Storage.Stub

  setup :set_mox_from_context

  setup do
    Stub.install_default_stubs()
    :ok
  end

  test "/health is 200 always", %{conn: conn} do
    assert conn |> get("/health") |> json_response(200) == %{"status" => "ok"}
  end

  test "/health/ready is 200 when deps are up", %{conn: conn} do
    resp = conn |> get("/health/ready") |> json_response(200)
    assert resp["status"] == "ok"
    assert resp["checks"]["db"] == true
    assert resp["checks"]["storage"] == true
  end

  test "/health/ready is 503 when storage fails", %{conn: conn} do
    stub(Stub.mock(), :bucket_reachable?, fn -> false end)

    resp = conn |> get("/health/ready") |> json_response(503)
    assert resp["status"] == "degraded"
    assert resp["checks"]["storage"] == false
  end
end
