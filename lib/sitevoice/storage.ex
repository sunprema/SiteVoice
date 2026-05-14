defmodule Sitevoice.Storage do
  @moduledoc false

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

  def store_audio(key, binary), do: store_typed(@audio_bucket, key, binary, "audio/m4a")
  def store_photo(key, binary), do: store_typed(@photo_bucket, key, binary, "image/jpeg")
  def store_pdf(key, binary), do: store_typed(@pdf_bucket, key, binary, "application/pdf")

  @spec store(bucket :: String.t(), key :: String.t(), body :: binary()) ::
          {:ok, String.t()} | {:error, term()}
  def store(bucket, key, body) do
    bucket
    |> ExAws.S3.put_object(key, body)
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_typed(bucket, key, binary, content_type) do
    bucket
    |> ExAws.S3.put_object(key, binary, content_type: content_type, server_side_encryption: "AES256")
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch(bucket :: String.t(), key :: String.t()) ::
          {:ok, binary()} | {:error, term()}
  def fetch(bucket, key) do
    bucket
    |> ExAws.S3.get_object(key)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec presigned_url(bucket :: String.t(), key :: String.t(), expires_in :: pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_url(bucket, key, expires_in) do
    config = ExAws.Config.new(:s3)

    ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: expires_in)
  end
end
