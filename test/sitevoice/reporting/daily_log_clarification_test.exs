defmodule Sitevoice.Reporting.DailyLogClarificationTest do
  use Sitevoice.DataCase, async: true

  use Oban.Testing, repo: Sitevoice.Repo

  @moduletag slice: :clarification

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog

  defp setup_org do
    {:ok, result} =
      RegisterOrganization.call(%{
        org_name: "Org #{System.unique_integer()}",
        user_email: "admin#{System.unique_integer()}@example.com",
        user_password: "password123",
        user_name: "Admin User"
      })

    result
  end

  defp create_foreman(org, admin) do
    {:ok, foreman} =
      User
      |> Ash.Changeset.for_create(
        :invite,
        %{
          email: "f#{System.unique_integer()}@example.com",
          name: "Foreman",
          role: :foreman
        },
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    foreman
  end

  defp create_project(org, admin) do
    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "P #{System.unique_integer()}", code: "C#{System.unique_integer()}"},
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    project
  end

  defp create_log(org, foreman, project) do
    {:ok, log} =
      DailyLog
      |> Ash.Changeset.for_create(
        :submit_recording,
        %{
          date: Date.utc_today(),
          audio_key: "k.m4a",
          audio_duration: 90,
          project_id: project.id
        },
        actor: foreman,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    log
  end

  describe ":request_clarification" do
    test "transitions status to :awaiting_clarification and persists questions" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      questions = [
        %{"question" => "How many crew?", "missing_field" => "labor"},
        %{"question" => "Any safety issues?", "missing_field" => "safety"}
      ]

      {:ok, updated} =
        log
        |> Ash.Changeset.for_update(:request_clarification, %{clarification_questions: questions},
          authorize?: false,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert updated.status == :awaiting_clarification
      assert length(updated.clarification_questions) == 2
    end
  end

  describe ":submit_clarification" do
    test "transitions to :processing and enqueues ClarificationProcessor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      {:ok, log} =
        log
        |> Ash.Changeset.for_update(:request_clarification, %{clarification_questions: []},
          authorize?: false,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      {:ok, updated} =
        log
        |> Ash.Changeset.for_update(
          :submit_clarification,
          %{clarification_audio_key: "k2.m4a", clarification_audio_duration: 10},
          actor: foreman,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert updated.status == :processing
      assert updated.clarification_audio_key == "k2.m4a"

      assert_enqueued(worker: Sitevoice.Workers.ClarificationProcessor)
    end

    test "rejects when clarification_round is already 1" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      {:ok, log} =
        log
        |> Ash.Changeset.for_update(
          :apply_clarification_structure,
          %{labor: [], progress: [], safety: [], accuracy_score: 0.5},
          authorize?: false,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert log.clarification_round == 1

      result =
        log
        |> Ash.Changeset.for_update(
          :submit_clarification,
          %{clarification_audio_key: "k.m4a", clarification_audio_duration: 5},
          actor: foreman,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert {:error, %Ash.Error.Invalid{}} = result
    end
  end

  describe ":skip_clarification" do
    test "transitions to :processing and enqueues FinalizeReportWorker" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      {:ok, log} =
        log
        |> Ash.Changeset.for_update(:request_clarification, %{clarification_questions: []},
          authorize?: false,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      {:ok, updated} =
        log
        |> Ash.Changeset.for_update(:skip_clarification, %{},
          actor: foreman,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert updated.status == :processing
      assert_enqueued(worker: Sitevoice.Workers.FinalizeReportWorker)
    end
  end

  describe ":apply_clarification_structure" do
    test "bumps clarification_round to 1 and transitions status to :draft" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)
      assert log.clarification_round == 0

      {:ok, updated} =
        log
        |> Ash.Changeset.for_update(
          :apply_clarification_structure,
          %{labor: [%{"crew" => "A"}], progress: [], safety: [], accuracy_score: 0.9},
          authorize?: false,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert updated.clarification_round == 1
      assert updated.status == :draft
    end
  end
end
