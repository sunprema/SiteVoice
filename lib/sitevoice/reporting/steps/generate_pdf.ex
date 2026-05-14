defmodule Sitevoice.Steps.GeneratePdf do
  use Reactor.Step

  @imprintor Application.compile_env(:sitevoice, :imprintor_mod, Imprintor)

  def run(%{log: log}, _, _) do
    template = File.read!(Application.app_dir(:sitevoice, "priv/templates/daily_log.typ"))

    data = %{
      "organization" => log.organization.name,
      "project" => log.project.name,
      "project_code" => log.project.code,
      "date" => Date.to_string(log.date),
      "foreman" => log.foreman.name,
      "submitted_at" => format_dt(log.submitted_at),
      "log_id" => log.id,
      "labor" => log.labor,
      "progress" => log.progress,
      "equipment" => log.equipment,
      "materials" => log.materials,
      "delays" => log.delays,
      "safety" => log.safety,
      "photos" => Enum.map(log.photos, fn photo ->
        %{
          "url" => photo.url || "",
          "caption" => photo.caption || "",
          "category" => to_string(photo.category || "")
        }
      end),
      "accuracy_score" => log.accuracy_score
    }

    config = Imprintor.Config.new(template, data, pdf_standard: "a-3a")

    case @imprintor.compile_to_pdf(config) do
      {:ok, binary} -> {:ok, binary}
      {:error, reason} -> {:error, "PDF failed: #{reason}"}
    end
  end

  def compensate(_, _, _, _), do: :ok

  defp format_dt(nil), do: "—"
  defp format_dt(dt), do: Calendar.strftime(dt, "%B %d, %Y %H:%M")
end
