defmodule Sitevoice.Integrations do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Integrations.Integration
    resource Sitevoice.Integrations.IntegrationEvent
  end
end
