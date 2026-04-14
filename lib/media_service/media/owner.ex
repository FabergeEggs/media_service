defmodule MediaService.Media.Owner do
  @allowed_kinds ~w(user project response task)

  defstruct [:kind, :id]

  @type t :: %__MODULE__{kind: String.t(), id: String.t()}

  def allowed_kinds, do: @allowed_kinds

  def valid_kind?(kind) when is_binary(kind), do: kind in @allowed_kinds
  def valid_kind?(_), do: false
end
