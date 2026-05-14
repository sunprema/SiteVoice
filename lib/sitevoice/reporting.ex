defmodule Sitevoice.Reporting do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Reporting.DailyLog
    resource Sitevoice.Reporting.DailyLog.Version
    resource Sitevoice.Reporting.Photo
  end
end
