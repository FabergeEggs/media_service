defmodule MediaService.Storage.Keys do
  @max_filename 180
  @fallback_name "file"

  @spec object_key(String.t(), String.t(), String.t(), String.t() | nil) :: String.t()
  def object_key(owner_kind, owner_id, asset_id, original_filename)
      when is_binary(owner_kind) and is_binary(owner_id) and is_binary(asset_id) do
    safe = sanitize_filename(original_filename)
    "#{owner_kind}/#{owner_id}/#{asset_id}/#{safe}"
  end

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
    ext = Path.extname(string)
    base = Path.rootname(string)
    base_allowance = max - byte_size(ext)

    cond do
      base_allowance > 0 -> binary_part(base, 0, min(base_allowance, byte_size(base))) <> ext
      true -> binary_part(string, 0, max)
    end
  end
end
