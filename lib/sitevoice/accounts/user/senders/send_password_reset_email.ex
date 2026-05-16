defmodule Sitevoice.Accounts.User.Senders.SendPasswordResetEmail do
  use AshAuthentication.Sender
  use SitevoiceWeb, :verified_routes

  import Swoosh.Email

  alias Sitevoice.Mailer

  @impl true
  def send(user, token, _opts) do
    invitation? = not is_nil(user.invited_at) and is_nil(user.confirmed_at)

    email =
      new()
      |> from({"SiteVoice AI", "noreply@sitevoice.ai"})
      |> to(to_string(user.email))

    email =
      if invitation? do
        email
        |> subject("You've been invited to SiteVoice AI")
        |> html_body(invitation_body(user: user, token: token))
      else
        email
        |> subject("Reset your SiteVoice password")
        |> html_body(reset_body(token: token))
      end

    Mailer.deliver!(email)
  end

  defp invitation_body(params) do
    url = url(~p"/password-reset/#{params[:token]}")
    name = params[:user].name

    """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0E1117;color:#C8D0DC;margin:0;padding:0}
      .c{max-width:560px;margin:40px auto;background:#1F2836;border:1px solid #3D4F65;border-radius:8px;overflow:hidden}
      .h{background:#FF5C00;padding:24px 32px}
      .h h1{margin:0;color:#EEF1F5;font-size:18px;font-weight:700;letter-spacing:2px;text-transform:uppercase}
      .b{padding:32px}
      .b p{margin:0 0 16px;line-height:1.6;color:#C8D0DC;font-size:15px}
      .btn{display:inline-block;background:#FF5C00;color:#EEF1F5!important;text-decoration:none;padding:14px 28px;border-radius:4px;font-weight:700;font-size:14px;letter-spacing:1px;text-transform:uppercase;margin:8px 0 24px}
      .f{padding:16px 32px;border-top:1px solid #3D4F65;font-size:12px;color:#3D4F65}
      .url{font-size:11px;color:#3D4F65;word-break:break-all}
    </style></head><body>
    <div class="c">
      <div class="h"><h1>SiteVoice AI — You're Invited</h1></div>
      <div class="b">
        <p>Hi #{name},</p>
        <p>You've been invited to join your team on <strong>SiteVoice AI</strong> — the platform that turns 90-second voice memos into professional daily logs.</p>
        <p>Click below to set your password and get started:</p>
        <a href="#{url}" class="btn">Set Your Password</a>
        <p>This link expires in 48 hours. If you didn't expect this, you can ignore this email.</p>
        <p class="url">#{url}</p>
      </div>
      <div class="f">SiteVoice AI · Built for field teams</div>
    </div>
    </body></html>
    """
  end

  defp reset_body(params) do
    url = url(~p"/password-reset/#{params[:token]}")

    """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0E1117;color:#C8D0DC;margin:0;padding:0}
      .c{max-width:560px;margin:40px auto;background:#1F2836;border:1px solid #3D4F65;border-radius:8px;overflow:hidden}
      .h{background:#1F2836;border-bottom:1px solid #3D4F65;padding:24px 32px}
      .h h1{margin:0;color:#EEF1F5;font-size:18px;font-weight:700;letter-spacing:2px;text-transform:uppercase}
      .b{padding:32px}
      .b p{margin:0 0 16px;line-height:1.6;color:#C8D0DC;font-size:15px}
      .btn{display:inline-block;background:#FF5C00;color:#EEF1F5!important;text-decoration:none;padding:14px 28px;border-radius:4px;font-weight:700;font-size:14px;letter-spacing:1px;text-transform:uppercase;margin:8px 0 24px}
      .f{padding:16px 32px;border-top:1px solid #3D4F65;font-size:12px;color:#3D4F65}
      .url{font-size:11px;color:#3D4F65;word-break:break-all}
    </style></head><body>
    <div class="c">
      <div class="h"><h1>Reset Your Password</h1></div>
      <div class="b">
        <p>We received a request to reset your SiteVoice AI password.</p>
        <p>Click the button below to choose a new password:</p>
        <a href="#{url}" class="btn">Reset Password</a>
        <p>This link expires in 48 hours. If you didn't request a reset, you can ignore this email.</p>
        <p class="url">#{url}</p>
      </div>
      <div class="f">SiteVoice AI · Built for field teams</div>
    </div>
    </body></html>
    """
  end
end
