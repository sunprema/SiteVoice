defmodule Sitevoice.Test.ImprintorStub do
  @moduledoc false

  def compile_to_pdf(config) do
    Application.put_env(:sitevoice, :imprintor_last_config, config)
    Application.get_env(:sitevoice, :imprintor_stub_result, {:ok, "fake-pdf-binary"})
  end
end
