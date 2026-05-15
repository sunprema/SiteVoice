defmodule Sitevoice.Steps.CaptionPhotos do
  use Reactor.Step

  require Logger

  def run(%{photo_keys: photos, transcript: transcript, organization_id: org_id}, _, _) do
    photo_count = length(photos)
    Logger.info("CaptionPhotos starting", photo_count: photo_count)

    updated =
      photos
      |> Enum.with_index(1)
      |> Enum.map(fn {photo, idx} ->
        Logger.debug("CaptionPhotos fetching photo",
          photo_id: photo.id,
          storage_key: photo.storage_key,
          index: idx,
          of: photo_count
        )

        with {:ok, binary} <- Sitevoice.Storage.fetch(photo.storage_key) do
          caption = generate_caption(Base.encode64(binary), transcript)
          category = infer_category(caption)

          Logger.debug(
            "CaptionPhotos applying caption — photo=#{photo.id} category=#{category} preview=#{String.slice(caption, 0, 80)}"
          )

          Ash.update!(photo, %{caption: caption, category: category},
            action: :apply_caption,
            actor: nil,
            tenant: org_id
          )
        else
          {:error, fetch_err} ->
            Logger.warning(
              "CaptionPhotos skipping photo=#{photo.id} key=#{photo.storage_key} — #{inspect(fetch_err)}"
            )

            photo
        end
      end)

    Logger.info("CaptionPhotos completed", photo_count: photo_count)
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
            Logger.warning("CaptionPhotos Claude API error status=#{s} body=#{body_preview} — using fallback")
            "Site photo"

          {:error, r} ->
            Logger.warning("CaptionPhotos Claude request failed — #{inspect(r)} — using fallback")
            "Site photo"
        end

      {result, %{}}
    end)
  end

  defp infer_category(caption) do
    cond do
      String.match?(caption, ~r/crack|issue|damage|delay|problem/i) -> :delays
      String.match?(caption, ~r/crane|equipment|machine/i) -> :equipment
      String.match?(caption, ~r/safety|hazard|ppe|harness/i) -> :safety
      String.match?(caption, ~r/material|delivery|concrete|rebar/i) -> :materials
      true -> :progress
    end
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
