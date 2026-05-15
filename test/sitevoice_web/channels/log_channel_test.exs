defmodule SitevoiceWeb.LogChannelTest do
  use SitevoiceWeb.ChannelCase, async: false

  @moduletag slice: :realtime

  alias Sitevoice.Accounts.Actions.RegisterOrganization
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

  defp create_project(org, actor) do
    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Test Project", code: "P#{System.unique_integer()}", timezone: "America/Phoenix"},
        actor: actor,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    project
  end

  defp create_log(org, actor, project) do
    {:ok, log} =
      DailyLog
      |> Ash.Changeset.for_create(
        :submit_recording,
        %{
          date: Date.utc_today(),
          audio_key: "#{org.id}/#{project.id}/#{Date.utc_today()}/test.m4a",
          audio_duration: 90,
          project_id: project.id
        },
        actor: actor,
        authorize?: false,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    log
  end

  defp token_for(%{__metadata__: %{token: token}}), do: token

  describe "join/3" do
    test "succeeds for a user in the org" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)
      log = create_log(org, admin, project)

      {:ok, socket} = connect(SitevoiceWeb.UserSocket, %{"token" => token_for(admin)})
      assert {:ok, _, _socket} = subscribe_and_join(socket, "log:#{log.id}", %{})
    end

    test "fails for a non-existent log_id" do
      %{organization: _org, user: admin} = setup_org()
      fake_log_id = Ecto.UUID.generate()

      {:ok, socket} = connect(SitevoiceWeb.UserSocket, %{"token" => token_for(admin)})

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, "log:#{fake_log_id}", %{})
    end
  end

  describe "handle_info/2" do
    test "forwards :report_ready to client" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)
      log = create_log(org, admin, project)

      {:ok, socket} = connect(SitevoiceWeb.UserSocket, %{"token" => token_for(admin)})
      {:ok, _, socket} = subscribe_and_join(socket, "log:#{log.id}", %{})

      send(socket.channel_pid, {:report_ready, %{log_id: log.id, pdf_url: "https://example.com/r.pdf"}})

      assert_push "report_ready", %{log_id: _, pdf_url: _}
    end

    test "forwards :pipeline_update to client" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)
      log = create_log(org, admin, project)

      {:ok, socket} = connect(SitevoiceWeb.UserSocket, %{"token" => token_for(admin)})
      {:ok, _, socket} = subscribe_and_join(socket, "log:#{log.id}", %{})

      send(socket.channel_pid, {:pipeline_update, %{step: "structured", status: :complete}})

      assert_push "pipeline_update", %{step: "structured", status: :complete}
    end

    test "forwards :pipeline_failed to client" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)
      log = create_log(org, admin, project)

      {:ok, socket} = connect(SitevoiceWeb.UserSocket, %{"token" => token_for(admin)})
      {:ok, _, socket} = subscribe_and_join(socket, "log:#{log.id}", %{})

      send(socket.channel_pid, {:pipeline_failed, %{reason: "claude_error"}})

      assert_push "pipeline_failed", %{reason: "claude_error"}
    end
  end
end
