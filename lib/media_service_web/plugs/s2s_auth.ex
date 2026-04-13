defmodule MediaServiceWeb.Plugs.S2SAuth do
  @moduledoc """
  Service-to-service authentication.

  MVP uses a shared secret passed in the `X-Service-Token` header. Each
  calling service has its own token in the `:media_service, :service_tokens`
  keyword-list config (key = service name, value = secret). The matched
  service name is stashed in `conn.assigns.caller_service` for audit.

  When Keycloak JWKS is wired in, this plug will be replaced with a JWT
  verifier — the shape of `conn.assigns.caller_service` stays the same, so
  controllers won't change.
  """

  import Plug.Conn

  alias Plug.Conn

  @header "x-service-token"

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Conn.t(), keyword()) :: Conn.t()
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
        else
          nil
        end
      end
    )
    |> case do
      :error -> :error
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
