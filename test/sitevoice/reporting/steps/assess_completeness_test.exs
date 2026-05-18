defmodule Sitevoice.Steps.AssessCompletenessTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :clarification

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Steps.AssessCompleteness

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

  defp create_project(org, admin, attrs \\ %{}) do
    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(%{name: "P #{System.unique_integer()}", code: "C#{System.unique_integer()}"}, attrs),
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    project
  end

  defp create_log(org, foreman, project, attrs) do
    {:ok, log} =
      DailyLog
      |> Ash.Changeset.for_create(
        :submit_recording,
        Map.merge(
          %{
            date: Date.utc_today(),
            audio_key: "k.m4a",
            audio_duration: 90,
            project_id: project.id
          },
          attrs
        ),
        actor: foreman,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    log
  end

  defp set_extracted(log, org, attrs) do
    {:ok, updated} =
      log
      |> Ash.Changeset.for_update(:apply_structure, attrs,
        authorize?: false,
        tenant: to_string(org.id)
      )
      |> Ash.update()

    updated
  end

  describe "run/3" do
    test "returns [] (complete) when all required sections are populated and accuracy is high" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project, %{})

      log =
        set_extracted(log, org, %{
          labor: [%{"crew" => "A", "headcount" => 4}],
          progress: [%{"description" => "x"}],
          safety: [%{"description" => "ok"}],
          accuracy_score: 0.9
        })

      assert {:ok, []} =
               AssessCompleteness.run(%{log: log, organization_id: to_string(org.id)}, nil, nil)
    end

    test "flags missing required sections" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project, %{})

      log =
        set_extracted(log, org, %{
          labor: [],
          progress: [],
          safety: [%{"description" => "ok"}],
          accuracy_score: 0.9
        })

      assert {:ok, missing} =
               AssessCompleteness.run(%{log: log, organization_id: to_string(org.id)}, nil, nil)

      assert :labor in missing
      assert :progress in missing
      refute :safety in missing
    end

    test "flags low accuracy" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project, %{})

      log =
        set_extracted(log, org, %{
          labor: [%{"crew" => "A"}],
          progress: [%{"description" => "x"}],
          safety: [%{"description" => "ok"}],
          accuracy_score: 0.4
        })

      assert {:ok, missing} =
               AssessCompleteness.run(%{log: log, organization_id: to_string(org.id)}, nil, nil)

      assert :accuracy in missing
    end

    test "respects per-project min accuracy threshold" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin, %{daily_log_min_accuracy: 0.95})
      log = create_log(org, foreman, project, %{})

      log =
        set_extracted(log, org, %{
          labor: [%{"crew" => "A"}],
          progress: [%{"description" => "x"}],
          safety: [%{"description" => "ok"}],
          accuracy_score: 0.85
        })

      assert {:ok, missing} =
               AssessCompleteness.run(%{log: log, organization_id: to_string(org.id)}, nil, nil)

      assert :accuracy in missing
    end

    test "returns [] when clarification_round >= 1 even if gaps remain" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project, %{})

      log =
        set_extracted(log, org, %{
          labor: [],
          progress: [],
          safety: [],
          accuracy_score: 0.4
        })

      # Simulate clarification already happened
      {:ok, log} =
        log
        |> Ash.Changeset.for_update(:apply_clarification_structure, %{
          labor: [],
          progress: [],
          safety: [],
          accuracy_score: 0.4
        }, authorize?: false, tenant: to_string(org.id))
        |> Ash.update()

      assert log.clarification_round == 1

      assert {:ok, []} =
               AssessCompleteness.run(%{log: log, organization_id: to_string(org.id)}, nil, nil)
    end
  end
end
