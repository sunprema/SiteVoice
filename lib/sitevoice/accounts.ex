defmodule Sitevoice.Accounts do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Accounts.Organization

    resource Sitevoice.Accounts.User do
      define :get_user_by_email, action: :get_by_email, args: [:email]
      define :list_users, action: :read
      define :invite_user, action: :invite
      define :update_user_role, action: :update_role
      define :update_profile, action: :update_profile
      define :change_password, action: :change_password
      define :deactivate_user, action: :deactivate
      define :reactivate_user, action: :reactivate
      define :remove_user, action: :destroy
    end

    resource Sitevoice.Accounts.Token
    resource Sitevoice.Accounts.User.Version
    resource Sitevoice.Accounts.ApiKey
  end
end
