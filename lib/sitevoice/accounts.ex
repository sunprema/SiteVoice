defmodule Sitevoice.Accounts do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Accounts.Organization
    resource Sitevoice.Accounts.Token
    resource Sitevoice.Accounts.User
    resource Sitevoice.Accounts.User.Version
    resource Sitevoice.Accounts.ApiKey
  end
end
