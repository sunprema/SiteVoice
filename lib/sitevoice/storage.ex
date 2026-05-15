defmodule Sitevoice.Storage do
  @moduledoc false

  require Logger

  @audio_bucket "sitevoice-audio"
  @photo_bucket "sitevoice-photos"
  @pdf_bucket "sitevoice-pdfs"

  def audio_key(org_id, project_id, date, log_id),
    do: "#{org_id}/#{project_id}/#{date}/#{log_id}.m4a"

  def photo_key(org_id, project_id, log_id, photo_id),
    do: "#{org_id}/#{project_id}/#{log_id}/#{photo_id}.jpg"

  def pdf_key(org_id, project_id, log_id) do
    d = Date.utc_today()
    "#{org_id}/#{project_id}/#{d.year}/#{d.month}/#{log_id}.pdf"
  end

  def store_audio(key, binary), do: store_labeled(@audio_bucket, key, binary, "audio/m4a", "audio")
  def store_photo(key, binary), do: store_labeled(@photo_bucket, key, binary, "image/jpeg", "photo")
  def store_pdf(key, binary), do: store_labeled(@pdf_bucket, key, binary, "application/pdf", "PDF")

  @spec store(bucket :: String.t(), key :: String.t(), body :: binary()) ::
          {:ok, String.t()} | {:error, term()}
  def store(bucket, key, body) do
    Logger.debug("Storage putting object", bucket: bucket, key: key, bytes: byte_size(body))

    bucket
    |> ExAws.S3.put_object(key, body)
    |> ExAws.request()
    |> case do
      {:ok, _} ->
        :telemetry.execute([:sitevoice, :storage, :store], %{bytes: byte_size(body)}, %{
          bucket: bucket,
          key: key
        })

        {:ok, key}

      {:error, reason} ->
        Logger.error("Storage put_object failed — bucket=#{bucket} key=#{key} reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  defp store_labeled(bucket, key, binary, content_type, label) do
    Logger.debug("Storage storing #{label}", key: key, bytes: byte_size(binary))
    store_typed(bucket, key, binary, content_type)
  end

  defp store_typed(bucket, key, binary, content_type) do
    bucket
    |> ExAws.S3.put_object(key, binary,
      content_type: content_type,
      server_side_encryption: "AES256"
    )
    |> ExAws.request()
    |> case do
      {:ok, _} ->
        :telemetry.execute([:sitevoice, :storage, :store], %{bytes: byte_size(binary)}, %{
          bucket: bucket,
          key: key,
          content_type: content_type
        })

        {:ok, key}

      {:error, reason} ->
        Logger.error(
          "Storage store_typed failed — bucket=#{bucket} key=#{key} content_type=#{content_type} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @photo_extensions ~w(.jpg .jpeg .png .webp .heic)

  @spec fetch(key :: String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch(key) when is_binary(key) do
    ext = key |> Path.extname() |> String.downcase()

    cond do
      ext == ".m4a" -> fetch(@audio_bucket, key)
      ext in @photo_extensions -> fetch(@photo_bucket, key)
      ext == ".pdf" -> fetch(@pdf_bucket, key)
      true ->
        Logger.error("Storage cannot determine bucket for key=#{key}")
        {:error, "Cannot determine bucket for key: #{key}"}
    end
  end

  @spec fetch(bucket :: String.t(), key :: String.t()) ::
          {:ok, binary()} | {:error, term()}
  def fetch(bucket, key) do
    Logger.debug("Storage fetching object", bucket: bucket, key: key)

    bucket
    |> ExAws.S3.get_object(key)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} ->
        :telemetry.execute([:sitevoice, :storage, :fetch], %{bytes: byte_size(body)}, %{
          bucket: bucket,
          key: key
        })

        {:ok, body}

      {:error, reason} ->
        Logger.error("Storage fetch failed — bucket=#{bucket} key=#{key} reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec presigned_url(bucket :: String.t(), key :: String.t(), expires_in :: pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_url(bucket, key, expires_in) do
    config = ExAws.Config.new(:s3)

    case ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: expires_in) do
      {:ok, _url} = result ->
        Logger.debug("Storage presigned URL generated", bucket: bucket, key: key, expires_in: expires_in)
        result

      {:error, reason} = result ->
        Logger.error(
          "Storage presigned URL failed — bucket=#{bucket} key=#{key} reason=#{inspect(reason)}"
        )

        result
    end
  end

end
