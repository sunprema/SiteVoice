defmodule SitevoiceWeb.SignOutLive do
  use SitevoiceWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    sign_out_path = Map.get(session, "sign_out_path", "/sign-out")
    {:ok, assign(socket, sign_out_path: sign_out_path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="sign-out-page">
      <div class="sign-out-glow"></div>

      <a href="/" class="sign-out-logo">
        Site<span>Voice</span>&nbsp;AI
      </a>

      <div class="sign-out-card">
        <div class="sign-out-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FF5C00" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>
            <polyline points="16 17 21 12 16 7"/>
            <line x1="21" y1="12" x2="9" y2="12"/>
          </svg>
        </div>

        <div class="sign-out-heading">SIGN OUT</div>

        <p class="sign-out-sub">
          You're about to sign out of SiteVoice AI.<br />
          Any unsaved recordings will be queued for later.
        </p>

        <.form for={%{}} action={@sign_out_path} method="delete">
          <button type="submit" class="sign-out-btn">
            Confirm Sign Out
          </button>
        </.form>

        <a href="/dashboard" class="sign-out-cancel">
          ← Back to Dashboard
        </a>
      </div>

      <div class="sign-out-footer">
        SITEVOICE AI · BUILT FOR THE FIELD
      </div>
    </div>
    """
  end
end
