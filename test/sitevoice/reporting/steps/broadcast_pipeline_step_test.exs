defmodule Sitevoice.Steps.BroadcastPipelineStepTest do
  use ExUnit.Case, async: false

  @moduletag slice: :realtime

  alias Sitevoice.Steps.BroadcastPipelineStep

  describe "run/3" do
    test "publishes pipeline_update on the org-namespaced topic" do
      org_id = Ecto.UUID.generate()
      log_id = Ecto.UUID.generate()
      topic = "org:#{org_id}:log:#{log_id}"

      Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)

      assert {:ok, :sent} =
               BroadcastPipelineStep.run(
                 %{step: "transcribed", log_id: log_id, organization_id: org_id},
                 nil,
                 nil
               )

      assert_receive {:pipeline_update, %{step: "transcribed", status: :complete}}
    end

    test "returns {:ok, :sent}" do
      org_id = Ecto.UUID.generate()
      log_id = Ecto.UUID.generate()

      assert {:ok, :sent} =
               BroadcastPipelineStep.run(
                 %{step: "structured", log_id: log_id, organization_id: org_id},
                 nil,
                 nil
               )
    end
  end

  describe "compensate/4" do
    test "returns :ok" do
      assert :ok = BroadcastPipelineStep.compensate(:reason, %{}, %{}, [])
    end
  end
end
