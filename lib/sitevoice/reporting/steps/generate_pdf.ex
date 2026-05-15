defmodule Sitevoice.Steps.GeneratePdf do
  use Reactor.Step

  require Logger

  @imprintor Application.compile_env(:sitevoice, :imprintor_mod, Imprintor)

  def run(%{log: log}, _, _) do
    Logger.info("GeneratePdf starting",
      log_id: log.id,
      project: log.project.name,
      date: Date.to_string(log.date),
      photo_count: length(log.photos)
    )

    template = File.read!(Application.app_dir(:sitevoice, "priv/templates/daily_log.typ"))

    data = %{
      "organization" => log.organization.name,
      "project" => log.project.name,
      "project_code" => log.project.code,
      "project_address" => log.project.address || "",
      "date" => Date.to_string(log.date),
      "foreman" => log.foreman.name,
      "submitted_at" => format_dt(log.submitted_at),
      "status" => to_string(log.status),
      "weather" => log.weather || "",
      "log_id" => log.id,
      "labor" => log.labor,
      "progress" => log.progress,
      "equipment" => log.equipment,
      "materials" => log.materials,
      "delays" => log.delays,
      "safety" => log.safety,
      "photos" =>
        Enum.map(log.photos, fn photo ->
          %{
            "caption" => photo.caption || "",
            "category" => to_string(photo.category || "")
          }
        end),
      "accuracy_score" => log.accuracy_score
    }

    config = Imprintor.Config.new(template, data, pdf_standard: "a-3a")

    :telemetry.span([:sitevoice, :pdf, :generate], %{log_id: log.id}, fn ->
      result =
        case @imprintor.compile_to_pdf(config) do
          {:ok, binary} ->
            Logger.info("GeneratePdf succeeded", log_id: log.id, pdf_bytes: byte_size(binary))
            {:ok, binary}

          {:error, reason} ->
            Logger.error("GeneratePdf compilation failed — log=#{log.id} reason=#{inspect(reason)}")
            {:error, "PDF compilation failed: #{inspect(reason)}"}
        end

      {result, %{}}
    end)
  end

  def compensate(_, _, _, _), do: :ok

  defp format_dt(nil), do: "—"
  defp format_dt(dt), do: Calendar.strftime(dt, "%B %d, %Y %H:%M")
end
