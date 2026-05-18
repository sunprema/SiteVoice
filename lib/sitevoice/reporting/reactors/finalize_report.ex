defmodule Sitevoice.Reporting.Reactors.FinalizeReport do
  @moduledoc """
  Runs the tail of the daily-log pipeline: caption photos, generate the PDF,
  upload it to Tigris, persist the key, and notify clients.

  This reactor is enqueued either by `ProcessRecording` when extraction is
  judged complete, or by `ProcessClarification` after the foreman has answered
  follow-up questions. Both entry points provide the same args.
  """

  use Ash.Reactor

  input :log_id
  input :organization_id

  step :set_tenant, Sitevoice.Steps.SetTenant do
    argument :organization_id, input(:organization_id)
  end

  step :fetch_log, Sitevoice.Steps.FetchLog do
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :set_tenant
  end

  step :caption_photos, Sitevoice.Steps.CaptionPhotos do
    argument :photo_keys, result(:fetch_log, [:photos])
    argument :transcript, result(:fetch_log, [:transcript])
    argument :organization_id, input(:organization_id)
    async? true
  end

  step :broadcast_photos_captioned, Sitevoice.Steps.BroadcastPipelineStep do
    argument :step, value("photos")
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :caption_photos
  end

  step :generate_pdf, Sitevoice.Steps.GeneratePdf do
    argument :log, result(:fetch_log)
    argument :organization_id, input(:organization_id)
    wait_for :caption_photos
  end

  step :broadcast_pdf_generated, Sitevoice.Steps.BroadcastPipelineStep do
    argument :step, value("pdf_generated")
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :generate_pdf
  end

  step :store_pdf, Sitevoice.Steps.StoreTigris do
    argument :binary, result(:generate_pdf)
    argument :key, input(:log_id)
    argument :organization_id, input(:organization_id)
    argument :project_id, result(:fetch_log, [:project_id])
  end

  update :save_pdf_key, Sitevoice.Reporting.DailyLog, :update_pdf do
    initial result(:fetch_log)
    tenant input(:organization_id)
    inputs %{pdf_key: result(:store_pdf, [:key])}
    wait_for :store_pdf
  end

  step :notify, Sitevoice.Steps.BroadcastReady do
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    argument :pdf_url, result(:store_pdf, [:url])
    wait_for :save_pdf_key
  end
end
