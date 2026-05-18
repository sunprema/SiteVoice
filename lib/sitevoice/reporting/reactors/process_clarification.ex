defmodule Sitevoice.Reporting.Reactors.ProcessClarification do
  @moduledoc """
  Runs after a foreman submits an addendum recording in response to
  clarification questions. Transcribes the addendum, merges it with the
  original extraction via Claude, persists the merged fields with
  `clarification_round` bumped to 1, then hands off to `FinalizeReport`.
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

  step :fetch_clarification_audio, Sitevoice.Steps.FetchFromTigris do
    argument :key, result(:fetch_log, [:clarification_audio_key])
  end

  step :transcribe_clarification, Sitevoice.Steps.TranscribeWhisper do
    argument :audio, result(:fetch_clarification_audio)
    argument :language, result(:fetch_log, [:foreman, :preferred_language])
  end

  update :save_clarification_transcript, Sitevoice.Reporting.DailyLog, :apply_clarification_transcript do
    initial result(:fetch_log)
    tenant input(:organization_id)
    inputs %{clarification_transcript: result(:transcribe_clarification)}
  end

  step :merge_clarification, Sitevoice.Steps.MergeClarification do
    argument :log, result(:save_clarification_transcript)
    argument :organization_id, input(:organization_id)
  end

  update :save_merged_structure, Sitevoice.Reporting.DailyLog, :apply_clarification_structure do
    initial result(:save_clarification_transcript)
    tenant input(:organization_id)
    inputs %{
      labor: result(:merge_clarification, [:labor]),
      progress: result(:merge_clarification, [:progress]),
      equipment: result(:merge_clarification, [:equipment]),
      materials: result(:merge_clarification, [:materials]),
      delays: result(:merge_clarification, [:delays]),
      safety: result(:merge_clarification, [:safety]),
      accuracy_score: result(:merge_clarification, [:accuracy_score])
    }
  end

  step :broadcast_structured, Sitevoice.Steps.BroadcastPipelineStep do
    argument :step, value("structured")
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :save_merged_structure
  end

  step :enqueue_finalize, Sitevoice.Steps.EnqueueFinalizeStep do
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :broadcast_structured
  end
end
