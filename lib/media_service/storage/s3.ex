defmodule MediaService.Storage.S3 do
  @behaviour MediaService.Storage.S3.Behaviour

  alias ExAws.S3

  @default_put_ttl 600
  @default_get_ttl 300

  @impl true
  def presign_put(object_key, opts \\ []) when is_binary(object_key) do
    bucket = bucket()
    ttl = Keyword.get(opts, :ttl, @default_put_ttl)

    headers =
      []
      |> maybe_put_header("content-type", Keyword.get(opts, :content_type))
      |> maybe_put_header("content-length", Keyword.get(opts, :content_length))

    ExAws.Config.new(:s3, aws_config_overrides())
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

    ExAws.Config.new(:s3, aws_config_overrides())
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
  def bucket, do: fetch_config!(:bucket)

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
