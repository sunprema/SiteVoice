defmodule Sitevoice.Repo.Migrations.CascadeDailyLogVersions do
  use Ecto.Migration

  def change do
    drop constraint(:daily_logs_versions, "daily_logs_versions_version_source_id_fkey")

    alter table(:daily_logs_versions) do
      modify :version_source_id,
             references(:daily_logs,
               column: :id,
               type: :uuid,
               on_delete: :delete_all
             )
    end
  end
end
