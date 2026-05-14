defmodule Sitevoice.Steps.StructureWithClaudeTest do
  use ExUnit.Case, async: true

  @moduletag slice: :ai_pipeline

  alias Sitevoice.Steps.StructureWithClaude

  @valid_response %{
    "labor" => [%{"crew" => "Martinez", "headcount" => 6}],
    "progress" => [],
    "equipment" => [],
    "materials" => [],
    "delays" => [],
    "safety" => [],
    "accuracy_score" => 0.92
  }

  setup do
    Req.Test.stub(:claude_req, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => Jason.encode!(@valid_response)}]
      })
    end)

    :ok
  end

  describe "run/3" do
    test "returns parsed map with atom keys on success" do
      assert {:ok, result} = StructureWithClaude.run(%{transcript: "Six workers poured rebar."}, %{}, [])

      assert is_map(result)
      assert Map.has_key?(result, :labor)
      assert Map.has_key?(result, :accuracy_score)
      assert result.accuracy_score == 0.92
    end

    test "returns error when response body is invalid JSON" do
      Req.Test.stub(:claude_req, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "not json at all"}]
        })
      end)

      assert {:error, "Invalid JSON from Claude: " <> _} =
               StructureWithClaude.run(%{transcript: "test"}, %{}, [])
    end

    test "returns error on non-200 response" do
      Req.Test.stub(:claude_req, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => "rate_limit"})
      end)

      assert {:error, "Claude 429: " <> _} =
               StructureWithClaude.run(%{transcript: "test"}, %{}, [])
    end
  end

  describe "compensate/4" do
    test "returns :ok" do
      assert :ok = StructureWithClaude.compensate(:reason, %{}, %{}, [])
    end
  end
end
