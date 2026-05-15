defmodule Sitevoice.Accounts do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Accounts.Organization

    resource Sitevoice.Accounts.User do
      define :get_user_by_email, action: :get_by_email, args: [:email]
    end

    resource Sitevoice.Accounts.Token
    resource Sitevoice.Accounts.User.Version
    resource Sitevoice.Accounts.ApiKey
  end
end
