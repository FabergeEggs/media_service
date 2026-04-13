defmodule MediaService.Media.Owner do
  @moduledoc """
  Owner of a media asset — value object identifying the business entity that
  holds the asset. Two fields: `kind` (string) and `id` (UUID).

  The media service itself does not validate whether the referenced entity
  exists or whether the caller has rights to it. That is the responsibility
  of the calling service (profile, project, response, ...). Here we only
  enforce that `kind` is one of the kinds we know about.
  """

  @allowed_kinds ~w(user project response task)

  defstruct [:kind, :id]

  @type t :: %__MODULE__{kind: String.t(), id: String.t()}

  @spec allowed_kinds() :: [String.t()]
  def allowed_kinds, do: @allowed_kinds

  @spec valid_kind?(String.t()) :: boolean()
  def valid_kind?(kind) when is_binary(kind), do: kind in @allowed_kinds
  def valid_kind?(_), do: false
end
