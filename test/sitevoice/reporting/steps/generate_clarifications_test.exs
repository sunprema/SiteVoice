defmodule Sitevoice.Steps.GenerateClarificationsTest do
  use Sitevoice.DataCase, async: false

  @moduletag slice: :clarification

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Steps.GenerateClarifications

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

  setup do
    prev = Application.get_env(:sitevoice, :anthropic_api_key)
    on_exit(fn -> Application.put_env(:sitevoice, :anthropic_api_key, prev) end)
    :ok
  end

  describe "template fallback" do
    test "returns deterministic questions when Claude API key is missing" do
      Application.put_env(:sitevoice, :anthropic_api_key, "")

      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      {:ok, questions} =
        GenerateClarifications.run(
          %{log: log, organization_id: to_string(org.id), missing: [:labor, :safety]},
          nil,
          nil
        )

      assert is_list(questions)
      assert length(questions) >= 1
      assert length(questions) <= 3

      assert Enum.any?(questions, fn q ->
               q["missing_field"] == "labor"
             end)
    end

    test "accuracy-only miss falls back to generic question" do
      Application.put_env(:sitevoice, :anthropic_api_key, "")

      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      {:ok, questions} =
        GenerateClarifications.run(
          %{log: log, organization_id: to_string(org.id), missing: [:accuracy]},
          nil,
          nil
        )

      assert [%{"question" => q}] = questions
      assert q =~ "summarize"
    end
  end
end
