defmodule SitevoiceWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import SitevoiceWeb.ChannelCase

      @endpoint SitevoiceWeb.Endpoint
    end
  end

  setup tags do
    Sitevoice.DataCase.setup_sandbox(tags)
    :ok
  end
end
