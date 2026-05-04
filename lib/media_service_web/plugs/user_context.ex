defmodule MediaServiceWeb.Plugs.UserContext do
  @moduledoc """
  Reads X-User-* headers (set by API gateway after JWT validation) into
  `conn.assigns.current_user`. Halts with 401 if `X-User-Id` is missing.

  Use on routes meant for end-users via the gateway. S2S routes keep
  using `S2SAuth` instead.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case header(conn, "x-user-id") do
      id when is_binary(id) and id != "" ->
        assign(conn, :current_user, %{
          id: id,
          name: header(conn, "x-username"),
          roles: parse_roles(header(conn, "x-user-roles"))
        })

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [v | _] -> v
      [] -> nil
    end
  end

  defp parse_roles(nil), do: []
  defp parse_roles(""), do: []

  defp parse_roles(csv) when is_binary(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
