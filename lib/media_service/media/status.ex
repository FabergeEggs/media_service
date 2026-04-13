defmodule MediaService.Media.Status do
  @moduledoc """
  State machine for `MediaService.Media.Asset`.

  MVP has three states:

      pending  — row created, caller obtained presigned PUT URL, bytes may or
                 may not be in MinIO yet.
      ready    — bytes confirmed in MinIO, asset is servable.
      deleted  — soft-deleted, bytes scheduled for purge.

  Allowed transitions:

      pending -> ready    (after complete)
      pending -> deleted  (abandoned upload)
      ready   -> deleted  (user/cascade delete)

  When the scanner / processor pipeline lands, intermediate states will be
  inserted between `pending` and `ready` (`scanning`, `processing`,
  `rejected`). The public API of this module is built to tolerate that:
  callers match on atoms, not on string values scattered through controllers.
  """

  @type t :: :pending | :ready | :deleted

  @all ~w(pending ready deleted)a

  @transitions %{
    pending: [:ready, :deleted],
    ready: [:deleted],
    deleted: []
  }

  @spec all() :: [t()]
  def all, do: @all

  @spec all_as_strings() :: [String.t()]
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
