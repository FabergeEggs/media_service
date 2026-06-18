defmodule MediaServiceWeb.Plugs.UserContext do
  # TODO(jwks-verification)

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

  defp resolve_user(conn) do
    case header(conn, "x-user-id") do
      id when is_binary(id) and id != "" ->
        {:ok, %{
          id: id,
          name: header(conn, "x-username"),
          roles: parse_roles(header(conn, "x-user-roles"))
        }}

      _ ->
        extract_from_bearer(conn)
    end
  end

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
