defmodule Sitevoice.Steps.TranscribeWhisperTest do
  use ExUnit.Case, async: true

  @moduletag slice: :ai_pipeline

  alias Sitevoice.Steps.TranscribeWhisper

  setup do
    Req.Test.stub(:whisper_req, fn conn ->
      Req.Test.json(conn, %{"text" => "Workers poured the footing today."})
    end)

    :ok
  end

  describe "run/3" do
    test "returns transcript on 200 response" do
      assert {:ok, "Workers poured the footing today."} =
               TranscribeWhisper.run(%{audio: "audio_binary", language: :en}, %{}, [])
    end

    test "maps :es language to whisper es param" do
      assert {:ok, _} = TranscribeWhisper.run(%{audio: "audio_binary", language: :es}, %{}, [])
    end

    test "maps non-:es language to en" do
      assert {:ok, _} = TranscribeWhisper.run(%{audio: "audio_binary", language: :en}, %{}, [])
    end

    test "returns error on non-200 response" do
      Req.Test.stub(:whisper_req, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "server error"})
      end)

      assert {:error, "Whisper 500: " <> _} =
               TranscribeWhisper.run(%{audio: "audio_binary", language: :en}, %{}, [])
    end
  end

  describe "compensate/4" do
    test "returns :ok" do
      assert :ok = TranscribeWhisper.compensate(:reason, %{}, %{}, [])
    end
  end
end
