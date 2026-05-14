defmodule Sitevoice.Repo.Migrations.DropVersionsFk do
  use Ecto.Migration

  def change do
    drop constraint(:daily_logs_versions, "daily_logs_versions_version_source_id_fkey")
  end
end
