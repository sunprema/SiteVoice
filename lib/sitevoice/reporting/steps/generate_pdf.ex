defmodule Sitevoice.Steps.GeneratePdf do
  use Reactor.Step

  require Logger

  @imprintor Application.compile_env(:sitevoice, :imprintor_mod, Imprintor)

  def run(%{log: log, organization_id: org_id}, _, _) do
    log = Ash.load!(log, [:photos], tenant: org_id, authorize?: false)

    Logger.info("GeneratePdf starting",
      log_id: log.id,
      project: log.project.name,
      date: Date.to_string(log.date),
      photo_count: length(log.photos)
    )

    tmp_dir = Path.join(System.tmp_dir!(), "sitevoice_pdf_#{log.id}")
    File.mkdir_p!(tmp_dir)

    try do
      {photos_data, root_dir} = prepare_photos(log.photos, tmp_dir)

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
        "photos" => photos_data,
        "accuracy_score" => log.accuracy_score
      }

      config = Imprintor.Config.new(template, data, pdf_standard: "a-3a", root_directory: root_dir)

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
    after
      File.rm_rf(tmp_dir)
    end
  end

  def compensate(_, _, _, _), do: :ok

  defp prepare_photos([], _tmp_dir), do: {[], "."}

  defp prepare_photos(photos, tmp_dir) do
    photos_data =
      Enum.flat_map(photos, fn photo ->
        case Sitevoice.Storage.fetch(photo.storage_key) do
          {:ok, bytes} ->
            ext = photo.storage_key |> Path.extname() |> String.downcase()
            filename = "#{photo.id}#{ext}"
            File.write!(Path.join(tmp_dir, filename), bytes)

            [%{
              "caption" => photo.caption || "",
              "category" => to_string(photo.category || ""),
              "filename" => filename
            }]

          {:error, reason} ->
            Logger.warning("GeneratePdf skipping photo — key=#{photo.storage_key} reason=#{inspect(reason)}")
            []
        end
      end)

    {photos_data, tmp_dir}
  end

  defp format_dt(nil), do: "—"
  defp format_dt(dt), do: Calendar.strftime(dt, "%B %d, %Y %H:%M")
end
