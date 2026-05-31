defmodule MediaServiceWeb.Plugs.UserContext do
  @moduledoc """
  Resolves the current user from the request, trying two strategies in order:

  1. **Gateway headers** — `X-User-Id` / `X-Username` / `X-User-Roles` injected by
     the API gateway after JWT validation. Preferred when running behind KrakenD.

  2. **Bearer token fallback** — if the gateway headers are absent (e.g. direct
     calls during development, or a KrakenD version that doesn't propagate claims
     with no-op encoding), the plug decodes the `Authorization: Bearer <jwt>` token
     and extracts the `sub` claim as the user ID.
     Signature verification is skipped here because the request must already
     have passed the gateway's JWT validator; this plug only extracts identity.
     TODO: add JWKS-based verification once the gateway header injection is stable.

  Halts with 401 if neither strategy yields a user ID.

  Use on routes meant for end-users via the gateway. S2S routes keep
  using `S2SAuth` instead.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case resolve_user(conn) do
      {:ok, user} ->
        assign(conn, :current_user, user)

      :error ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  # Strategy 1: gateway-injected headers
  defp resolve_user(conn) do
    case header(conn, "x-user-id") do
      id when is_binary(id) and id != "" ->
        {:ok, %{
          id: id,
          name: header(conn, "x-username"),
          roles: parse_roles(header(conn, "x-user-roles"))
        }}

      _ ->
        # Strategy 2: extract sub from Bearer token
        extract_from_bearer(conn)
    end
  end

  # Decode JWT body without signature verification (trust the gateway validated it).
  defp extract_from_bearer(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         [_header, payload_b64, _sig] <- String.split(token, "."),
         {:ok, payload_json} <- Base.url_decode64(payload_b64, padding: false),
         {:ok, %{"sub" => sub}} <- Jason.decode(payload_json),
         true <- is_binary(sub) and sub != "" do
      {:ok, %{id: sub, name: nil, roles: []}}
    else
      _ -> :error
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
