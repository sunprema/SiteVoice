defmodule Sitevoice.Steps.StoreTigris do
  use Reactor.Step

  def run(%{binary: <<>>, key: _key, organization_id: _org_id}, _, _) do
    {:ok, %{url: nil}}
  end

  def run(%{binary: binary, key: log_id, organization_id: org_id}, _, _) do
    key = Sitevoice.Storage.pdf_key(org_id, org_id, log_id)

    with {:ok, _} <- Sitevoice.Storage.store_pdf(key, binary),
         {:ok, url} <- Sitevoice.Storage.presigned_url("sitevoice-pdfs", key, 3600) do
      {:ok, %{url: url}}
    end
  end

  def compensate(_, _, _, _), do: :ok
end
