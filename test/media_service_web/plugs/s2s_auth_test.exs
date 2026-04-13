defmodule MediaServiceWeb.Plugs.S2SAuthTest do
  use MediaServiceWeb.ConnCase, async: true

  alias MediaServiceWeb.Plugs.S2SAuth

  describe "call/2" do
    test "401 without token" do
      conn = build_conn() |> S2SAuth.call([])
      assert conn.halted
      assert conn.status == 401
    end

    test "401 with unknown token" do
      conn =
        build_conn()
        |> put_req_header("x-service-token", "nonsense")
        |> S2SAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "assigns caller_service on valid token" do
      conn =
        build_conn()
        |> put_req_header("x-service-token", "test-profile-token")
        |> S2SAuth.call([])

      refute conn.halted
      assert conn.assigns[:caller_service] == "profile-service"
    end
  end
end
