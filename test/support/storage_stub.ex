defmodule MediaService.Storage.Stub do
  @moduledoc """
  Test helpers on top of the Mox-generated `MediaService.Storage.S3Mock`.

  Tests call `Stub.allow_presign/0` etc. to wire up the most common
  happy-path expectations without repeating the same `Mox.stub/3` calls in
  every test module.
  """

  import Mox

  @bucket "test-bucket"

  @spec mock() :: module()
  def mock, do: MediaService.Storage.S3Mock

  @spec bucket() :: String.t()
  def bucket, do: @bucket

  @doc """
  Install default happy-path stubs for every callback. Individual tests can
  override with `Mox.expect/4` as needed.
  """
  @spec install_default_stubs() :: :ok
  def install_default_stubs do
    stub(mock(), :bucket, fn -> @bucket end)

    stub(mock(), :presign_put, fn object_key, opts ->
      {:ok,
       %{
         url: "http://minio.test/#{@bucket}/#{object_key}?sig=put",
         expires_in: Keyword.get(opts, :ttl, 600),
         headers: []
       }}
    end)

    stub(mock(), :presign_get, fn object_key, opts ->
      {:ok,
       %{
         url: "http://minio.test/#{@bucket}/#{object_key}?sig=get",
         expires_in: Keyword.get(opts, :ttl, 300)
       }}
    end)

    stub(mock(), :head_object, fn _object_key ->
      {:ok,
       %{
         content_length: 123,
         content_type: "image/jpeg",
         etag: "\"stub-etag\"",
         last_modified: "Wed, 16 Apr 2026 00:00:00 GMT"
       }}
    end)

    stub(mock(), :delete_object, fn _object_key -> :ok end)
    stub(mock(), :bucket_reachable?, fn -> true end)

    :ok
  end
end
