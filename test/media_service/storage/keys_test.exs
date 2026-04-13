defmodule MediaService.Storage.KeysTest do
  use ExUnit.Case, async: true

  alias MediaService.Storage.Keys

  describe "sanitize_filename/1" do
    test "returns fallback for nil and empty" do
      assert Keys.sanitize_filename(nil) == "file"
      assert Keys.sanitize_filename("") == "file"
    end

    test "strips path traversal attempts" do
      assert Keys.sanitize_filename("../../etc/passwd") == "passwd"
      assert Keys.sanitize_filename("/tmp/evil.sh") == "evil.sh"
    end

    test "replaces disallowed characters with underscore" do
      assert Keys.sanitize_filename("hello world.jpg") == "hello_world.jpg"
      assert Keys.sanitize_filename("a&b|c.png") == "a_b_c.png"
    end

    test "collapses repeated underscores and dots" do
      assert Keys.sanitize_filename("a   b....jpg") == "a_b.jpg"
    end

    test "trims leading dots" do
      assert Keys.sanitize_filename("...secret.txt") == "secret.txt"
    end

    test "keeps unicode letters" do
      assert Keys.sanitize_filename("Файл.jpg") == "Файл.jpg"
    end

    test "clips long names but keeps extension" do
      long = String.duplicate("a", 300) <> ".jpg"
      out = Keys.sanitize_filename(long)
      assert String.ends_with?(out, ".jpg")
      assert byte_size(out) <= 180
    end
  end

  describe "object_key/4" do
    test "builds prefixed key" do
      key = Keys.object_key("project", "proj-1", "asset-1", "hi there.jpg")
      assert key == "project/proj-1/asset-1/hi_there.jpg"
    end
  end
end
