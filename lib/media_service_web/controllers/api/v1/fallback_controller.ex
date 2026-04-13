defmodule MediaServiceWeb.API.V1.FallbackController do
  @moduledoc """
  Centralised error-to-HTTP mapping used via `action_fallback/1` in the
  controllers. Keeps controller actions focused on the happy path.
  """

  use MediaServiceWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  def call(conn, {:error, {:missing_params, fields}}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_params", fields: fields})
  end

  def call(conn, {:error, :invalid_size}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_size"})
  end

  def call(conn, {:error, :invalid_status}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "invalid_status"})
  end

  def call(conn, {:error, {:invalid_status, current}}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "invalid_status", current: Atom.to_string(current)})
  end

  def call(conn, {:error, {:size_mismatch, detail}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "size_mismatch", detail: detail})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_failed", details: translate_changeset(changeset)})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:bad_gateway)
    |> json(%{error: "storage_error", detail: inspect(reason)})
  end

  defp translate_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
