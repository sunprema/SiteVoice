defmodule SitevoiceWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Sitevoice.Projects],
    open_api: "/open_api"
end
