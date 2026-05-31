defmodule MediaService.Storage.S3.Behaviour do
  @type object_key :: String.t()
  @type presign_opts :: keyword()

  @type put_result :: %{url: String.t(), expires_in: pos_integer(), headers: keyword()}
  @type get_result :: %{url: String.t(), expires_in: pos_integer()}

  @type head :: %{
          content_length: non_neg_integer() | nil,
          content_type: String.t() | nil,
          etag: String.t() | nil,
          last_modified: String.t() | nil
        }

  @callback presign_put(object_key(), presign_opts()) :: {:ok, put_result()} | {:error, term()}
  @callback presign_get(object_key(), presign_opts()) :: {:ok, get_result()} | {:error, term()}
  @callback head_object(object_key()) :: {:ok, head()} | {:error, term()}
  @callback delete_object(object_key()) :: :ok | {:error, term()}
  @callback bucket_reachable?() :: boolean()
  @callback bucket() :: String.t()

  # Direct upload — stores raw binary to S3 via internal client (no presigned URL).
  # Used by the server-side upload proxy endpoint.
  @callback put_object(object_key(), body :: binary(), opts :: keyword()) ::
              :ok | {:error, term()}
end
