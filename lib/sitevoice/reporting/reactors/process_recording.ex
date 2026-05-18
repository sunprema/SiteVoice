defmodule Sitevoice.Reporting.Reactors.ProcessRecording do
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

  step :fetch_audio, Sitevoice.Steps.FetchFromTigris do
    argument :key, result(:fetch_log, [:audio_key])
  end

  step :transcribe, Sitevoice.Steps.TranscribeWhisper do
    argument :audio, result(:fetch_audio)
    argument :language, result(:fetch_log, [:foreman, :preferred_language])
  end

  update :save_transcript, Sitevoice.Reporting.DailyLog, :apply_transcript do
    initial result(:fetch_log)
    tenant input(:organization_id)
    inputs %{transcript: result(:transcribe)}
    undo :always
    undo_action :undo_apply_transcript
  end

  step :broadcast_transcribed, Sitevoice.Steps.BroadcastPipelineStep do
    argument :step, value("transcribed")
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :save_transcript
  end

  step :fetch_attendance, Sitevoice.Steps.FetchAttendance do
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :set_tenant
  end

  step :structure, Sitevoice.Steps.StructureWithClaude do
    argument :transcript, result(:transcribe)
    argument :project, result(:fetch_log, [:project])
    async? true
  end

  step :merge_labor, Sitevoice.Steps.MergeAttendanceLabor do
    argument :attendance, result(:fetch_attendance)
    argument :claude_labor, result(:structure, [:labor])
    wait_for :structure
    wait_for :fetch_attendance
  end

  update :save_structure, Sitevoice.Reporting.DailyLog, :apply_structure do
    initial result(:save_transcript)
    tenant input(:organization_id)
    inputs %{
      labor: result(:merge_labor),
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

  step :assess_completeness, Sitevoice.Steps.AssessCompleteness do
    argument :log, result(:save_structure)
    argument :organization_id, input(:organization_id)
    wait_for :broadcast_structured
  end

  switch :complete_or_clarify do
    on result(:assess_completeness)

    matches? &(&1 == []) do
      step :enqueue_finalize, Sitevoice.Steps.EnqueueFinalizeStep do
        argument :log_id, input(:log_id)
        argument :organization_id, input(:organization_id)
      end
    end

    default do
      step :generate_clarifications, Sitevoice.Steps.GenerateClarifications do
        argument :log, result(:save_structure)
        argument :organization_id, input(:organization_id)
        argument :missing, result(:assess_completeness)
      end

      update :save_clarification_request, Sitevoice.Reporting.DailyLog, :request_clarification do
        initial result(:save_structure)
        tenant input(:organization_id)
        inputs %{clarification_questions: result(:generate_clarifications)}
      end

      step :broadcast_clarification_needed, Sitevoice.Steps.BroadcastClarificationNeeded do
        argument :log_id, input(:log_id)
        argument :organization_id, input(:organization_id)
        argument :questions, result(:generate_clarifications)
        wait_for :save_clarification_request
      end
    end
  end
end
