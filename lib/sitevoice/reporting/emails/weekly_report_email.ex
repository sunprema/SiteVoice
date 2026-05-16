defmodule Sitevoice.Reporting.Emails.WeeklyReportEmail do
  import Swoosh.Email

  def report_ready(report, pdf_binary, pm) do
    new()
    |> to({pm.name, to_string(pm.email)})
    |> from({"SiteVoice", "reports@sitevoice.app"})
    |> subject("Weekly Report — #{report.project.name} · #{format_date(report.week_start)} – #{format_date(report.week_end)}")
    |> html_body(report_html(report, pm))
    |> text_body(report_text(report))
    |> attachment(
      Swoosh.Attachment.new(
        {:data, pdf_binary},
        filename: "weekly-report-#{report.week_start}.pdf",
        content_type: "application/pdf"
      )
    )
  end

  defp report_html(report, pm) do
    accomplishments_html =
      report.key_accomplishments
      |> Enum.map_join("", fn a ->
        ~s(<li style="margin-bottom: 6px; font-size: 13px; color: #374151;">#{escape(a)}</li>)
      end)

    issues_html =
      report.outstanding_issues
      |> Enum.map_join("", fn i ->
        ~s(<li style="margin-bottom: 6px; font-size: 13px; color: #991b1b;">#{escape(i)}</li>)
      end)

    accomplishments_section =
      if accomplishments_html == "" do
        ""
      else
        """
        <tr>
          <td style="background:#f0fdf4;padding:16px 32px;border-left:3px solid #16a34a;margin:0 32px;">
            <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;color:#16a34a;text-transform:uppercase;margin-bottom:10px;">Key Accomplishments</div>
            <ul style="margin:0;padding-left:16px;">#{accomplishments_html}</ul>
          </td>
        </tr>
        """
      end

    issues_section =
      if issues_html == "" do
        ""
      else
        """
        <tr>
          <td style="background:#fef2f2;padding:16px 32px;border-left:3px solid #ef4444;margin:0 32px;">
            <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;color:#dc2626;text-transform:uppercase;margin-bottom:10px;">Outstanding Issues</div>
            <ul style="margin:0;padding-left:16px;">#{issues_html}</ul>
          </td>
        </tr>
        """
      end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>Weekly Report</title>
    </head>
    <body style="margin:0;padding:0;background:#f4f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:32px 16px;">
        <tr><td align="center">
          <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

            <tr>
              <td style="background:#1a2332;border-radius:8px 8px 0 0;padding:28px 32px;">
                <div style="font-size:11px;font-weight:700;letter-spacing:2px;color:#f97316;text-transform:uppercase;margin-bottom:6px;">SiteVoice</div>
                <div style="font-size:22px;font-weight:700;color:#ffffff;">Weekly Summary Report</div>
                <div style="font-size:13px;color:#94a3b8;margin-top:6px;">#{escape(report.project.name)} · #{format_date(report.week_start)} – #{format_date(report.week_end)}</div>
              </td>
            </tr>

            <tr>
              <td style="background:#ffffff;padding:24px 32px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td width="33%" style="vertical-align:top;">
                      <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Days Logged</div>
                      <div style="font-size:20px;font-weight:700;color:#111827;">#{report.daily_log_count || 0}</div>
                    </td>
                    <td width="33%" style="vertical-align:top;">
                      <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Total Hours</div>
                      <div style="font-size:20px;font-weight:700;color:#111827;">#{format_hours(report.total_labor_hours)}</div>
                    </td>
                    <td width="33%" style="vertical-align:top;">
                      <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Worker-Days</div>
                      <div style="font-size:20px;font-weight:700;color:#111827;">#{report.total_headcount_days || 0}</div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td style="background:#ffffff;padding:20px 32px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;">
                <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;color:#f97316;text-transform:uppercase;margin-bottom:12px;">Executive Summary</div>
                <div style="font-size:13px;line-height:1.7;color:#374151;white-space:pre-line;">#{escape(report.summary)}</div>
              </td>
            </tr>

            #{accomplishments_section}
            #{issues_section}

            <tr>
              <td style="background:#1a2332;border-radius:0 0 8px 8px;padding:20px 32px;">
                <div style="font-size:12px;color:#9ca3af;">Hi #{escape(pm.name)}, the full weekly report PDF is attached.</div>
              </td>
            </tr>

          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  defp report_text(report) do
    accomplishments =
      report.key_accomplishments
      |> Enum.map_join("\n", &"  • #{&1}")

    issues =
      report.outstanding_issues
      |> Enum.map_join("\n", &"  • #{&1}")

    """
    Weekly Report — #{report.project.name}
    Week: #{report.week_start} – #{report.week_end}

    SUMMARY
    #{report.summary}

    KEY ACCOMPLISHMENTS
    #{if accomplishments == "", do: "  None recorded", else: accomplishments}

    OUTSTANDING ISSUES
    #{if issues == "", do: "  None", else: issues}

    Days logged: #{report.daily_log_count || 0}
    Total labor hours: #{format_hours(report.total_labor_hours)}
    Total worker-days: #{report.total_headcount_days || 0}

    The full PDF report is attached.
    """
  end

  defp format_date(%Date{} = d) do
    month =
      ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
      |> Enum.at(d.month - 1)

    "#{month} #{d.day}, #{d.year}"
  end

  defp format_hours(nil), do: "0"
  defp format_hours(h) when is_float(h), do: :erlang.float_to_binary(h, decimals: 1)
  defp format_hours(h), do: to_string(h)

  defp escape(nil), do: ""

  defp escape(str) do
    str
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
