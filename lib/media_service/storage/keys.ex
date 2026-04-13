defmodule MediaService.Storage.Keys do
  @moduledoc """
  Pure functions that build safe S3/MinIO object keys and sanitise user-supplied
  filenames. No IO — everything here is deterministic.

  Object key layout:

      <owner_kind>/<owner_id>/<asset_id>/<safe_filename>

  When the scanner pipeline is added, a `quarantine/` prefix will be used for
  the initial upload and assets will be copied to the layout above only after
  they pass the scan. Today we go straight to the final key.
  """

  @max_filename 180
  @fallback_name "file"

  @doc """
  Build the object key for an asset that lives in its final location.
  """
  @spec object_key(String.t(), String.t(), String.t(), String.t() | nil) :: String.t()
  def object_key(owner_kind, owner_id, asset_id, original_filename)
      when is_binary(owner_kind) and is_binary(owner_id) and is_binary(asset_id) do
    safe = sanitize_filename(original_filename)
    "#{owner_kind}/#{owner_id}/#{asset_id}/#{safe}"
  end

  @doc """
  Sanitise a user-supplied filename:

    * Unicode-normalise to NFC
    * Strip any path components (`../../etc/passwd` -> `passwd`)
    * Keep only letters, digits, `.`, `-`, `_`
    * Collapse duplicates, trim leading dots, clip length
    * Fall back to a placeholder if the result is empty
  """
  @spec sanitize_filename(String.t() | nil) :: String.t()
  def sanitize_filename(nil), do: @fallback_name
  def sanitize_filename(""), do: @fallback_name

  def sanitize_filename(name) when is_binary(name) do
    name
    |> :unicode.characters_to_nfc_binary()
    |> Path.basename()
    |> String.replace(~r/[^\p{L}\p{N}\.\-_]/u, "_")
    |> String.replace(~r/_+/, "_")
    |> String.replace(~r/\.+/, ".")
    |> String.trim_leading(".")
    |> clip(@max_filename)
    |> case do
      "" -> @fallback_name
      value -> value
    end
  end

  defp clip(string, max) when byte_size(string) <= max, do: string

  defp clip(string, max) do
    # Truncate but preserve the file extension if it fits.
    ext = Path.extname(string)
    base = Path.rootname(string)

    base_allowance = max - byte_size(ext)

    cond do
      base_allowance > 0 -> binary_part(base, 0, min(base_allowance, byte_size(base))) <> ext
      true -> binary_part(string, 0, max)
    end
  end
end
