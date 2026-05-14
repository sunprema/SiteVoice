defmodule Sitevoice.Storage do
  @moduledoc false

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
