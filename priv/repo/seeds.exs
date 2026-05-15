# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Safe to re-run — skips anything that already exists.

require Ash.Query

alias Sitevoice.Accounts.{User, Organization}
alias Sitevoice.Projects.{Project, ProjectMembership}

IO.puts("==> Seeding dev PM user and project memberships...")

orgs = Ash.read!(Organization, authorize?: false)

if orgs == [] do
  IO.puts("No organisations found — register via the app first, then re-run seeds.")
else
  Enum.each(orgs, fn org ->
    org_id = org.id
    IO.puts("  Org: #{org.name} (#{org_id})")

    # We need an org_admin actor for ProjectMembership.add_member
    actor =
      User
      |> Ash.Query.filter(organization_id == ^org_id and role == :org_admin)
      |> Ash.read_one!(authorize?: false)

    if is_nil(actor) do
      IO.puts("  No org_admin found — skipping org #{org.name}")
    else
      pm_email = "pm@sitevoice.dev"

      existing_pm =
        User
        |> Ash.Query.filter(organization_id == ^org_id and email == ^pm_email)
        |> Ash.read_one!(authorize?: false)

      pm_user =
        if existing_pm do
          IO.puts("  PM user already exists (#{pm_email})")
          existing_pm
        else
          IO.puts("  Creating PM user: #{pm_email}")

          Ash.create!(
            User,
            %{
              email: pm_email,
              password: "password123!",
              password_confirmation: "password123!",
              organization_id: org_id,
              name: "Project Manager",
              role: :pm
            },
            action: :register_with_password,
            authorize?: false,
            tenant: org_id
          )
        end

      projects =
        Project
        |> Ash.Query.filter(active == true)
        |> Ash.read!(authorize?: false, tenant: org_id)

      IO.puts("  Found #{length(projects)} active project(s)")

      Enum.each(projects, fn project ->
        existing_membership =
          ProjectMembership
          |> Ash.Query.filter(user_id == ^pm_user.id and project_id == ^project.id)
          |> Ash.read_one!(authorize?: false, tenant: org_id)

        if existing_membership do
          IO.puts("  Already a member of '#{project.name}' — skipping")
        else
          Ash.create!(
            ProjectMembership,
            %{user_id: pm_user.id, project_id: project.id, role: :pm},
            action: :add_member,
            actor: actor,
            authorize?: false,
            tenant: org_id
          )

          IO.puts("  Added PM to project '#{project.name}'")
        end
      end)
    end
  end)

  IO.puts("""

  Done.
    PM email:    pm@sitevoice.dev
    PM password: password123!
    Dev mailbox: http://localhost:4000/dev/mailbox
  """)
end
