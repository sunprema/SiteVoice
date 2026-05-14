defmodule Sitevoice.Accounts do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Accounts.Token
    resource Sitevoice.Accounts.User
    resource Sitevoice.Accounts.ApiKey
  end
end
