defmodule MediaServiceWeb.Plugs.S2SAuth do
  import Plug.Conn

  @header "x-service-token"

  def init(opts), do: opts

  def call(conn, _opts) do
    with [token | _] <- get_req_header(conn, @header),
         {:ok, service} <- verify(token) do
      assign(conn, :caller_service, service)
    else
      _ -> unauthorized(conn)
    end
  end

  defp verify(token) when is_binary(token) and byte_size(token) > 0 do
    Enum.find_value(
      Application.get_env(:media_service, :service_tokens, []),
      :error,
      fn {service, expected} ->
        if Plug.Crypto.secure_compare(token, to_string(expected)) do
          {:ok, to_string(service)}
        end
      end
    )
    |> case do
      nil -> :error
      other -> other
    end
  end

  defp verify(_), do: :error

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end
