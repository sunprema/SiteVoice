defmodule Sitevoice.Steps.StoreWeeklyPdf do
  use Reactor.Step

  require Logger

  @pdf_bucket "sitevoice-pdfs"

  def run(%{binary: binary, report_id: report_id, organization_id: org_id}, _, _) do
    key = "#{org_id}/weekly-reports/#{report_id}.pdf"
    pdf_bytes = byte_size(binary)

    Logger.info("StoreWeeklyPdf uploading", storage_key: key, pdf_bytes: pdf_bytes)

    :telemetry.span([:sitevoice, :storage, :store_weekly_pdf], %{bytes: pdf_bytes}, fn ->
      result =
        with {:ok, _} <- Sitevoice.Storage.store_pdf(key, binary) do
          Logger.info("StoreWeeklyPdf uploaded", storage_key: key)
          {:ok, key}
        else
          {:error, reason} ->
            Logger.error("StoreWeeklyPdf failed", storage_key: key, reason: inspect(reason))
            {:error, reason}
        end

      {result, %{}}
    end)
  end

  def compensate(%{report_id: report_id, organization_id: org_id}, _, _, _) do
    key = "#{org_id}/weekly-reports/#{report_id}.pdf"

    @pdf_bucket
    |> ExAws.S3.delete_object(key)
    |> ExAws.request()

    :ok
  end
end
