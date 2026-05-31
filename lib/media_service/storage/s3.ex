defmodule MediaService.Storage.S3 do
  @behaviour MediaService.Storage.S3.Behaviour

  alias ExAws.S3

  @default_put_ttl 600
  # 7 days — AWS Signature V4 maximum for presigned URLs (604800 s).
  # profile_service stores download_url — on expiry the frontend must re-fetch
  # via GET /me/assets/{id} to get a fresh URL.
  @default_get_ttl 604_800

  @impl true
  def presign_put(object_key, opts \\ []) when is_binary(object_key) do
    bucket = bucket()
    ttl = Keyword.get(opts, :ttl, @default_put_ttl)

    headers =
      []
      |> maybe_put_header("content-type", Keyword.get(opts, :content_type))
      |> maybe_put_header("content-length", Keyword.get(opts, :content_length))

    # Use public config so the URL is reachable from the browser / external client.
    ExAws.Config.new(:s3, aws_public_config_overrides())
    |> S3.presigned_url(:put, bucket, object_key,
      expires_in: ttl,
      query_params: [],
      headers: headers
    )
    |> case do
      {:ok, url} -> {:ok, %{url: url, expires_in: ttl, headers: headers}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def presign_get(object_key, opts \\ []) when is_binary(object_key) do
    bucket = bucket()
    ttl = Keyword.get(opts, :ttl, @default_get_ttl)

    # Use public config so the URL is reachable from the browser / external client.
    ExAws.Config.new(:s3, aws_public_config_overrides())
    |> S3.presigned_url(:get, bucket, object_key, expires_in: ttl)
    |> case do
      {:ok, url} -> {:ok, %{url: url, expires_in: ttl}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def head_object(object_key) when is_binary(object_key) do
    bucket()
    |> S3.head_object(object_key)
    |> ExAws.request(aws_config_overrides())
    |> case do
      {:ok, %{headers: headers, status_code: 200}} -> {:ok, normalize_head(headers)}
      {:ok, %{status_code: status}} -> {:error, {:http, status}}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_object(object_key) when is_binary(object_key) do
    bucket()
    |> S3.delete_object(object_key)
    |> ExAws.request(aws_config_overrides())
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def bucket_reachable? do
    bucket()
    |> S3.head_bucket()
    |> ExAws.request(aws_config_overrides())
    |> case do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def put_object(object_key, body, opts \\ []) when is_binary(object_key) and is_binary(body) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    bucket()
    |> S3.put_object(object_key, body, content_type: content_type)
    |> ExAws.request(aws_config_overrides())
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def bucket, do: fetch_config!(:bucket)

  # Used for internal S3 API calls (head, delete, put, reachability check).
  # Points to the internal Docker network hostname (e.g. "minio").
  # For regular (non-presigned) requests, ExAws derives the canonical host
  # from the full URL it builds, so port is included automatically.
  defp aws_config_overrides do
    [
      access_key_id: fetch_config!(:access_key_id),
      secret_access_key: fetch_config!(:secret_access_key),
      region: Keyword.get(config(), :region, "us-east-1"),
      scheme: Keyword.get(config(), :scheme, "http://"),
      host: fetch_config!(:host),
      port: Keyword.get(config(), :port, 9000),
      s3: [scheme: Keyword.get(config(), :scheme, "http://")]
    ]
  end

  # Used only for presigned URL generation (GET download URLs, S2S upload URLs).
  # Uses MINIO_PUBLIC_HOST / MINIO_PUBLIC_PORT so the resulting URL is reachable
  # by the browser. In Docker Compose set MINIO_PUBLIC_HOST=localhost.
  #
  # ExAws v2.6+ correctly includes the non-standard port in the canonical host
  # when signing (i.e. signs "host:localhost:9000"), so host + port as separate
  # keys works correctly as long as credentials are correct.
  defp aws_public_config_overrides do
    cfg = config()
    public_host = Keyword.get(cfg, :public_host, fetch_config!(:host))
    public_port = Keyword.get(cfg, :public_port, Keyword.get(cfg, :port, 9000))
    scheme = Keyword.get(cfg, :scheme, "http://")

    [
      access_key_id: fetch_config!(:access_key_id),
      secret_access_key: fetch_config!(:secret_access_key),
      region: Keyword.get(cfg, :region, "us-east-1"),
      scheme: scheme,
      host: public_host,
      port: public_port,
      s3: [scheme: scheme]
    ]
  end

  defp config, do: Application.get_env(:media_service, __MODULE__, [])

  defp fetch_config!(key) do
    case Keyword.fetch(config(), key) do
      {:ok, value} -> value
      :error -> raise "Missing :media_service, #{inspect(__MODULE__)}, #{inspect(key)} config"
    end
  end

  defp maybe_put_header(headers, _name, nil), do: headers
  defp maybe_put_header(headers, name, value), do: [{name, to_string(value)} | headers]

  defp normalize_head(headers) do
    map =
      headers
      |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
      |> Map.new()

    %{
      content_length: parse_integer(Map.get(map, "content-length")),
      content_type: Map.get(map, "content-type"),
      etag: Map.get(map, "etag"),
      last_modified: Map.get(map, "last-modified")
    }
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_integer(value) when is_integer(value), do: value
end
