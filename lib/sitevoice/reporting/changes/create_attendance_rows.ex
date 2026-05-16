defmodule Sitevoice.Reporting.Changes.CreateAttendanceRows do
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      create_rows(log)
      {:ok, log}
    end)
  end

  defp create_rows(log) do
    org_id = log.organization_id

    templates =
      case Ash.read(Sitevoice.Reporting.CrewTemplate,
             action: :list_for_project,
             arguments: %{project_id: log.project_id},
             authorize?: false,
             tenant: org_id
           ) do
        {:ok, templates} -> templates
        {:error, err} ->
          Logger.warning("CreateAttendanceRows could not load crew templates: #{inspect(err)}")
          []
      end

    Enum.each(templates, fn tmpl ->
      params = %{
        headcount_present: tmpl.default_headcount,
        headcount_absent: 0,
        hours: 8.0,
        daily_log_id: log.id,
        crew_template_id: tmpl.id,
        organization_id: org_id
      }

      case Ash.create(Sitevoice.Reporting.DailyAttendance, params,
             action: :create_from_system,
             authorize?: false,
             tenant: org_id
           ) do
        {:ok, _} ->
          Logger.debug("CreateAttendanceRows created row for crew=#{tmpl.name}")

        {:error, err} ->
          Logger.warning(
            "CreateAttendanceRows failed for crew=#{tmpl.name}: #{inspect(err)}"
          )
      end
    end)
  end
end
