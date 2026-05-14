defmodule Sitevoice.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Sitevoice.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:sitevoice, :token_signing_secret)
  end
end
