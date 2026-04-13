defmodule MediaService.Media.StatusTest do
  use ExUnit.Case, async: true

  alias MediaService.Media.Status

  test "to_atom accepts strings and atoms" do
    assert Status.to_atom("pending") == {:ok, :pending}
    assert Status.to_atom(:ready) == {:ok, :ready}
    assert Status.to_atom("bogus") == :error
    assert Status.to_atom(nil) == :error
  end

  test "allowed transitions" do
    assert Status.can_transition?(:pending, :ready)
    assert Status.can_transition?(:pending, :deleted)
    assert Status.can_transition?(:ready, :deleted)
  end

  test "forbidden transitions" do
    refute Status.can_transition?(:ready, :pending)
    refute Status.can_transition?(:deleted, :ready)
    refute Status.can_transition?(:deleted, :deleted)
  end
end
