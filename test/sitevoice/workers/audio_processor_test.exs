defmodule Sitevoice.Workers.AudioProcessorTest do
  use Sitevoice.DataCase, async: true
  use Oban.Testing, repo: Sitevoice.Repo

  @moduletag slice: :recording

  alias Sitevoice.Workers.AudioProcessor

  describe "perform/1" do
    test "returns :ok" do
      job = %Oban.Job{
        args: %{"log_id" => Ecto.UUID.generate(), "organization_id" => Ecto.UUID.generate()}
      }

      assert :ok = AudioProcessor.perform(job)
    end

    test "accepts log_id and organization_id from job args" do
      log_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      job = %Oban.Job{args: %{"log_id" => log_id, "organization_id" => org_id}}

      assert :ok = AudioProcessor.perform(job)
    end
  end
end
