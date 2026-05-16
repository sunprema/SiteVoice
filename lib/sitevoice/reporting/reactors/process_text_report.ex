defmodule Sitevoice.Reporting.Reactors.ProcessTextReport do
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

  # Broadcast "transcribed" immediately since the transcript is already in the DB.
  step :broadcast_transcribed, Sitevoice.Steps.BroadcastPipelineStep do
    argument :step, value("transcribed")
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :fetch_log
  end

  step :structure, Sitevoice.Steps.StructureWithClaude do
    argument :transcript, result(:fetch_log, [:transcript])
    wait_for :broadcast_transcribed
    async? true
  end

  step :caption_photos, Sitevoice.Steps.CaptionPhotos do
    argument :photo_keys, result(:fetch_log, [:photos])
    argument :transcript, result(:fetch_log, [:transcript])
    argument :organization_id, input(:organization_id)
    wait_for :broadcast_transcribed
    async? true
  end

  step :broadcast_photos_captioned, Sitevoice.Steps.BroadcastPipelineStep do
    argument :step, value("photos")
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :caption_photos
  end

  update :save_structure, Sitevoice.Reporting.DailyLog, :apply_structure do
    initial result(:fetch_log)
    tenant input(:organization_id)

    inputs %{
      labor: result(:structure, [:labor]),
      progress: result(:structure, [:progress]),
      equipment: result(:structure, [:equipment]),
      materials: result(:structure, [:materials]),
      delays: result(:structure, [:delays]),
      safety: result(:structure, [:safety]),
      accuracy_score: result(:structure, [:accuracy_score])
    }

    undo :always
    undo_action :undo_apply_structure
  end

  step :broadcast_structured, Sitevoice.Steps.BroadcastPipelineStep do
    argument :step, value("structured")
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :save_structure
  end

  step :generate_pdf, Sitevoice.Steps.GeneratePdf do
    argument :log, result(:save_structure)
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
  end
end
