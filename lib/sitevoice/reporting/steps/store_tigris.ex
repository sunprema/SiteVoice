defmodule Sitevoice.Steps.StoreTigris do
  use Reactor.Step

  require Logger

  def run(%{binary: <<>>, key: log_id, organization_id: org_id, project_id: _project_id}, _, _) do
    Logger.warning("StoreTigris received empty PDF binary, skipping upload",
      log_id: log_id,
      org_id: org_id
    )

    {:ok, %{url: nil, key: nil}}
  end

  def run(%{binary: binary, key: log_id, organization_id: org_id, project_id: project_id}, _, _) do
    key = Sitevoice.Storage.pdf_key(org_id, project_id, log_id)
    pdf_bytes = byte_size(binary)

    Logger.info("StoreTigris uploading PDF", storage_key: key, pdf_bytes: pdf_bytes)

    :telemetry.span([:sitevoice, :storage, :store_pdf], %{log_id: log_id, bytes: pdf_bytes}, fn ->
      result =
        with {:ok, _} <- Sitevoice.Storage.store_pdf(key, binary),
             {:ok, url} <- Sitevoice.Storage.presigned_url("sitevoice-pdfs", key, 3600) do
          Logger.info("StoreTigris PDF uploaded and URL signed", storage_key: key)
          {:ok, %{url: url, key: key}}
        else
          {:error, reason} ->
            Logger.error("StoreTigris failed to upload PDF",
              storage_key: key,
              reason: inspect(reason)
            )

            {:error, reason}
        end

      {result, %{}}
    end)
  end

  def compensate(_, _, _, _), do: :ok
end
