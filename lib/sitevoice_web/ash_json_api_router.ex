defmodule SitevoiceWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Sitevoice.Projects, Sitevoice.Reporting],
    open_api: "/open_api"
end
