defmodule MediaService.Media.Status do
  @type t :: :pending | :scanning | :ready | :rejected | :deleted

  @all ~w(pending scanning ready rejected deleted)a

  @transitions %{
    pending: [:scanning, :deleted],
    scanning: [:ready, :rejected, :deleted],
    ready: [:deleted],
    rejected: [:deleted],
    deleted: []
  }

  def all, do: @all
  def all_as_strings, do: Enum.map(@all, &Atom.to_string/1)

  @spec can_transition?(t(), t()) :: boolean()
  def can_transition?(from, to) when from in @all and to in @all do
    to in Map.fetch!(@transitions, from)
  end

  def can_transition?(_, _), do: false

  @spec to_atom(String.t() | atom()) :: {:ok, t()} | :error
  def to_atom(value) when is_atom(value) and value in @all, do: {:ok, value}

  def to_atom(value) when is_binary(value) do
    case Enum.find(@all, &(Atom.to_string(&1) == value)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  def to_atom(_), do: :error
end
