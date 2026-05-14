defmodule Sitevoice.Steps.GeneratePdfTest do
  use ExUnit.Case, async: false

  @moduletag slice: :pdf_generation

  alias Sitevoice.Steps.GeneratePdf

  defp build_log do
    org_id = Ecto.UUID.generate()

    %Sitevoice.Reporting.DailyLog{
      id: Ecto.UUID.generate(),
      organization_id: org_id,
      date: ~D[2024-01-15],
      status: :draft,
      labor: [%{"crew" => "Martinez", "headcount" => "6", "trade" => "Carpenter", "hours" => "8"}],
      progress: [%{"description" => "Poured south footing", "location" => "South wing"}],
      equipment: [%{"item" => "Crane", "status" => "operational"}],
      materials: [%{"item" => "Rebar", "quantity" => "200", "received_at" => "2024-01-15"}],
      delays: [],
      safety: [%{"description" => "All workers wore PPE"}],
      accuracy_score: 0.88,
      submitted_at: nil,
      organization: %Sitevoice.Accounts.Organization{
        id: org_id,
        name: "Test Org"
      },
      project: %Sitevoice.Projects.Project{
        id: Ecto.UUID.generate(),
        organization_id: org_id,
        name: "Test Project",
        code: "P001",
        timezone: "America/Phoenix"
      },
      foreman: %Sitevoice.Accounts.User{
        id: Ecto.UUID.generate(),
        organization_id: org_id,
        name: "John Doe",
        email: "john@example.com",
        role: :foreman
      },
      photos: []
    }
  end

  setup do
    Application.delete_env(:sitevoice, :imprintor_stub_result)
    Application.delete_env(:sitevoice, :imprintor_last_config)
    on_exit(fn ->
      Application.delete_env(:sitevoice, :imprintor_stub_result)
      Application.delete_env(:sitevoice, :imprintor_last_config)
    end)
    :ok
  end

  describe "run/3 — happy path" do
    test "returns {:ok, binary} when Imprintor succeeds" do
      log = build_log()
      assert {:ok, "fake-pdf-binary"} = GeneratePdf.run(%{log: log}, nil, nil)
    end

    test "passes string-keyed data map to Imprintor" do
      log = build_log()
      assert {:ok, _} = GeneratePdf.run(%{log: log}, nil, nil)

      config = Application.get_env(:sitevoice, :imprintor_last_config)
      assert is_map(config.data)

      assert config.data["organization"] == "Test Org"
      assert config.data["project"] == "Test Project"
      assert config.data["project_code"] == "P001"
      assert config.data["date"] == "2024-01-15"
      assert config.data["foreman"] == "John Doe"
      assert config.data["log_id"] == log.id
    end

    test "data map contains all six structured categories" do
      log = build_log()
      assert {:ok, _} = GeneratePdf.run(%{log: log}, nil, nil)

      config = Application.get_env(:sitevoice, :imprintor_last_config)

      assert Map.has_key?(config.data, "labor")
      assert Map.has_key?(config.data, "progress")
      assert Map.has_key?(config.data, "equipment")
      assert Map.has_key?(config.data, "materials")
      assert Map.has_key?(config.data, "delays")
      assert Map.has_key?(config.data, "safety")
    end

    test "photos are mapped to string-keyed maps with url, caption, category" do
      photo = %Sitevoice.Reporting.Photo{
        id: Ecto.UUID.generate(),
        organization_id: "org",
        daily_log_id: "log",
        storage_key: "org/log/p1.jpg",
        caption: "South footing pour",
        category: :progress,
        url: "https://example.com/photo.jpg"
      }

      log = %{build_log() | photos: [photo]}
      assert {:ok, _} = GeneratePdf.run(%{log: log}, nil, nil)

      config = Application.get_env(:sitevoice, :imprintor_last_config)
      [mapped_photo] = config.data["photos"]

      assert mapped_photo["caption"] == "South footing pour"
      assert mapped_photo["category"] == "progress"
      assert mapped_photo["url"] == "https://example.com/photo.jpg"
    end

    test "submitted_at nil formats as em-dash" do
      log = %{build_log() | submitted_at: nil}
      assert {:ok, _} = GeneratePdf.run(%{log: log}, nil, nil)

      config = Application.get_env(:sitevoice, :imprintor_last_config)
      assert config.data["submitted_at"] == "—"
    end

    test "submitted_at datetime formats correctly" do
      {:ok, dt, _} = DateTime.from_iso8601("2024-01-15T14:30:00Z")
      log = %{build_log() | submitted_at: dt}
      assert {:ok, _} = GeneratePdf.run(%{log: log}, nil, nil)

      config = Application.get_env(:sitevoice, :imprintor_last_config)
      assert config.data["submitted_at"] == "January 15, 2024 14:30"
    end
  end

  describe "run/3 — error path" do
    test "returns {:error, message} when Imprintor fails" do
      Application.put_env(:sitevoice, :imprintor_stub_result, {:error, "template error"})
      log = build_log()
      assert {:error, "PDF failed: template error"} = GeneratePdf.run(%{log: log}, nil, nil)
    end
  end

  describe "compensate/4" do
    test "returns :ok" do
      assert :ok = GeneratePdf.compensate(:reason, %{}, %{}, [])
    end
  end
end
