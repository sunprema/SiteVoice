defmodule Sitevoice.Steps.CaptionPhotoEntries do
  use Reactor.Step

  require Logger

  def run(%{entries: entries, transcript: transcript, organization_id: org_id}, _, _) do
    photo_entries = Enum.filter(entries, &(&1.type == :photo))
    photo_count = length(photo_entries)
    Logger.info("CaptionPhotoEntries starting", photo_count: photo_count)

    updated =
      photo_entries
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, idx} ->
        Logger.debug("CaptionPhotoEntries fetching photo",
          entry_id: entry.id,
          photo_key: entry.photo_key,
          index: idx,
          of: photo_count
        )

        with {:ok, binary} <- Sitevoice.Storage.fetch(entry.photo_key) do
          caption = generate_caption(Base.encode64(binary), transcript)

          Logger.debug("CaptionPhotoEntries applying caption — entry=#{entry.id} preview=#{String.slice(caption, 0, 80)}")

          Ash.update!(entry, %{caption: caption},
            action: :apply_caption,
            authorize?: false,
            tenant: org_id
          )
        else
          {:error, fetch_err} ->
            Logger.warning(
              "CaptionPhotoEntries skipping entry=#{entry.id} key=#{entry.photo_key} — #{inspect(fetch_err)}"
            )

            entry
        end
      end)

    Logger.info("CaptionPhotoEntries completed", photo_count: photo_count)
    {:ok, updated}
  end

  def compensate(_, _, _, _), do: :ok

  defp generate_caption(b64, transcript) do
    body = %{
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        %{
          role: "user",
          content: [
            %{type: "image", source: %{type: "base64", media_type: "image/jpeg", data: b64}},
            %{
              type: "text",
              text: """
              Construction site photo. Foreman context: #{String.slice(transcript, 0, 300)}.
              Write a single concise caption (max 15 words) for a daily construction log.
              """
            }
          ]
        }
      ]
    }

    :telemetry.span([:sitevoice, :claude, :caption], %{}, fn ->
      result =
        case Req.post(
               "https://api.anthropic.com/v1/messages",
               [
                 json: body,
                 headers: [{"x-api-key", api_key()}, {"anthropic-version", "2023-06-01"}],
                 receive_timeout: 30_000
               ] ++ Application.get_env(:sitevoice, :anthropic_req_options, [])
             ) do
          {:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}} ->
            String.trim(t)

          {:ok, %{status: s, body: b}} ->
            body_preview = b |> inspect() |> String.slice(0, 300)
            Logger.warning("CaptionPhotoEntries Claude error status=#{s} body=#{body_preview} — using fallback")
            "Site photo"

          {:error, r} ->
            Logger.warning("CaptionPhotoEntries Claude failed — #{inspect(r)} — using fallback")
            "Site photo"
        end

      {result, %{}}
    end)
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
