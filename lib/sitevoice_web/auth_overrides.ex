defmodule SitevoiceWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{
    Components,
    ConfirmLive,
    ResetLive,
    SignInLive
  }

  # ─── Page wrappers ──────────────────────────────────────────────────────────
  override SignInLive do
    set :root_class, "auth-page"
  end

  override ResetLive do
    set :root_class, "auth-page"
  end

  override ConfirmLive do
    set :root_class, "auth-page"
  end

  # ─── Card ───────────────────────────────────────────────────────────────────
  override Components.SignIn do
    set :root_class, "auth-card"
    set :strategy_class, nil
    set :show_banner, true
    set :authentication_error_container_class, "auth-alert-error"
    set :authentication_error_text_class, "auth-alert-error-text"
    set :strategy_display_order, :forms_first
  end

  # ─── Logo banner ────────────────────────────────────────────────────────────
  override Components.Banner do
    set :root_class, "auth-banner"
    set :href_url, "/"
    set :href_class, "auth-logo-link"
    set :image_url, nil
    set :dark_image_url, nil
    set :text_class, nil
    set :text, "SiteVoice AI"
  end

  # ─── Password strategy wrapper ───────────────────────────────────────────────
  override Components.Password do
    set :root_class, nil
    set :interstitial_class, "auth-interstitial"
    set :toggler_class, "auth-toggler"
    set :sign_in_toggle_text, "Need an account? Register →"
    set :register_toggle_text, "Already have an account? Sign in"
    set :reset_toggle_text, "Forgot password?"
    set :hide_class, "auth-hidden"
    set :show_first, :sign_in
  end

  # ─── Sign-in form ────────────────────────────────────────────────────────────
  override Components.Password.SignInForm do
    set :root_class, nil
    set :label_class, "auth-form-heading"
    set :form_class, "auth-form"
    set :button_text, "Sign In"
    set :disable_button_text, "Signing in…"
  end

  # ─── Register form ───────────────────────────────────────────────────────────
  override Components.Password.RegisterForm do
    set :root_class, nil
    set :label_class, "auth-form-heading"
    set :form_class, "auth-form"
    set :button_text, "Create Account"
    set :disable_button_text, "Creating account…"
  end

  # ─── Reset request form (embedded in sign-in page toggle) ───────────────────
  override Components.Password.ResetForm do
    set :root_class, nil
    set :label_class, "auth-form-heading"
    set :form_class, "auth-form"
    set :button_text, "Send Reset Link"
    set :disable_button_text, "Sending…"

    set :reset_flash_text,
        "If this email exists in our system, you'll receive a reset link shortly."
  end

  # ─── Reset page (token link from email → set new password) ──────────────────
  override Components.Reset do
    set :root_class, "auth-card"
    set :strategy_class, nil
    set :show_banner, true
  end

  override Components.Reset.Form do
    set :root_class, nil
    set :label_class, "auth-form-heading"
    set :form_class, "auth-form"
    set :spacer_class, nil
    set :button_text, "Reset Password"
    set :disable_button_text, "Saving…"
  end

  # ─── Confirm email page ──────────────────────────────────────────────────────
  override Components.Confirm do
    set :root_class, "auth-card"
    set :strategy_class, nil
    set :show_banner, true
  end

  override Components.Confirm.Form do
    set :root_class, "auth-confirm-body"
    set :label_class, "auth-form-heading"
    set :form_class, "auth-form"
    set :disable_button_text, "Confirming…"
  end

  override Components.Confirm.Input do
    set :submit_label, "Confirm Email Address"
    set :submit_class, "auth-submit"
  end

  # ─── Input fields ────────────────────────────────────────────────────────────
  override Components.Password.Input do
    set :field_class, "auth-field"
    set :label_class, "auth-label"
    set :input_class, "auth-input"
    set :input_class_with_error, "auth-input auth-input--error"
    set :submit_class, "auth-submit"
    set :identity_input_label, "Email Address"
    set :password_input_label, "Password"
    set :password_confirmation_input_label, "Confirm Password"
    set :error_ul, "auth-error-list"
    set :error_li, "auth-error-item"
    set :input_debounce, 350
  end

  # ─── Magic link ──────────────────────────────────────────────────────────────
  override Components.MagicLink do
    set :root_class, nil
    set :label_class, "auth-form-heading"
    set :form_class, "auth-form"
    set :request_flash_text,
        "If this email exists, you'll receive a sign-in link shortly."
    set :disable_button_text, "Sending…"
  end

  override Components.MagicLink.Input do
    set :submit_class, "auth-submit"
    set :submit_label, "Send Magic Link"
    set :input_debounce, 350
  end

  # ─── Flash messages ──────────────────────────────────────────────────────────
  override Components.Flash do
    set :message_class_info, "auth-flash auth-flash--info"
    set :message_class_error, "auth-flash auth-flash--error"
  end

  # ─── Horizontal rule between strategies ──────────────────────────────────────
  override Components.HorizontalRule do
    set :root_class, "auth-divider"
    set :hr_outer_class, "auth-divider-line"
    set :hr_inner_class, nil
    set :text_outer_class, "auth-divider-text-wrap"
    set :text_inner_class, "auth-divider-text"
    set :text, "or"
  end
end
