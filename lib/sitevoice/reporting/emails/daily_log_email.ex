defmodule Sitevoice.Reporting.Emails.DailyLogEmail do
  import Swoosh.Email

  def report_ready(log, pdf_binary, pm) do
    new()
    |> to({pm.name, to_string(pm.email)})
    |> from({"SiteVoice", "reports@sitevoice.app"})
    |> subject("Daily Log — #{log.project.name} · #{format_date(log.date)}")
    |> html_body(report_html(log, pm))
    |> text_body(report_text(log))
    |> attachment(
      Swoosh.Attachment.new(
        {:data, pdf_binary},
        filename: "daily-log-#{log.date}.pdf",
        content_type: "application/pdf"
      )
    )
  end

  def daily_reminder(foreman) do
    new()
    |> to({foreman.name, to_string(foreman.email)})
    |> from({"SiteVoice", "reminders@sitevoice.app"})
    |> subject("Reminder: Submit your daily log for #{Date.utc_today()}")
    |> text_body("Hi #{foreman.name}, don't forget to submit your daily site log today.")
  end

  # ---------------------------------------------------------------------------
  # HTML builder — pre-compute each section so no heredocs are nested
  # ---------------------------------------------------------------------------

  defp report_html(log, pm) do
    weather_row    = weather_html(log.weather)
    transcript_sec = transcript_html(log)
    progress_sec   = section_html("Progress", log.progress, &progress_item/1)
    labor_sec      = labor_table_html(log.labor)
    equipment_sec  = section_html("Equipment", log.equipment, &equipment_item/1)
    materials_sec  = section_html("Materials", log.materials, &materials_item/1)
    delays_sec     = section_html("Delays", log.delays, &delays_item/1)
    safety_sec     = section_html("Safety", log.safety, &safety_item/1)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Daily Site Log</title>
    </head>
    <body style="margin:0;padding:0;background:#f4f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:32px 16px;">
        <tr><td align="center">
          <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

            <!-- Header -->
            <tr>
              <td style="background:#1a2332;border-radius:8px 8px 0 0;padding:28px 32px;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td>
                      <div style="font-size:11px;font-weight:700;letter-spacing:2px;color:#f97316;text-transform:uppercase;margin-bottom:6px;">SiteVoice</div>
                      <div style="font-size:22px;font-weight:700;color:#ffffff;">Daily Site Log</div>
                    </td>
                    <td align="right" style="vertical-align:top;">
                      <div style="background:#f97316;color:#ffffff;font-size:12px;font-weight:700;padding:6px 14px;border-radius:20px;display:inline-block;">SUBMITTED</div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <!-- Project Info -->
            <tr>
              <td style="background:#ffffff;padding:24px 32px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td width="50%" style="padding-bottom:12px;vertical-align:top;">
                      <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Project</div>
                      <div style="font-size:15px;font-weight:600;color:#111827;">#{escape(log.project.name)}</div>
                      <div style="font-size:12px;color:#6b7280;margin-top:2px;">#{escape(log.project.code)}</div>
                    </td>
                    <td width="50%" style="padding-bottom:12px;vertical-align:top;">
                      <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Date</div>
                      <div style="font-size:15px;font-weight:600;color:#111827;">#{format_date(log.date)}</div>
                    </td>
                  </tr>
                  <tr>
                    <td width="50%" style="vertical-align:top;">
                      <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Location</div>
                      <div style="font-size:13px;color:#374151;">#{escape(log.project.address || "—")}</div>
                    </td>
                    <td width="50%" style="vertical-align:top;">
                      <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Submitted By</div>
                      <div style="font-size:13px;color:#374151;">#{escape(log.foreman.name)}</div>
                    </td>
                  </tr>
                  #{weather_row}
                </table>
              </td>
            </tr>

            #{divider()}
            #{transcript_sec}
            #{progress_sec}
            #{labor_sec}
            #{equipment_sec}
            #{materials_sec}
            #{delays_sec}
            #{safety_sec}

            <!-- Footer -->
            <tr>
              <td style="background:#1a2332;border-radius:0 0 8px 8px;padding:20px 32px;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td>
                      <div style="font-size:12px;color:#9ca3af;">Hi #{escape(pm.name)}, the full PDF report is attached to this email.</div>
                    </td>
                    <td align="right">
                      <div style="font-size:11px;color:#4b5563;">SiteVoice · Daily Logs</div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  defp divider do
    ~s(<tr><td style="background:#ffffff;padding:0 32px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;"><div style="border-top:1px solid #f3f4f6;"></div></td></tr>)
  end

  defp weather_html(nil), do: ""

  defp weather_html(weather) do
    """
    <tr>
      <td colspan="2" style="padding-top:12px;vertical-align:top;">
        <div style="font-size:10px;font-weight:600;letter-spacing:1px;color:#9ca3af;text-transform:uppercase;margin-bottom:4px;">Weather</div>
        <div style="font-size:13px;color:#374151;">#{escape(weather)}</div>
      </td>
    </tr>
    """
  end

  defp transcript_html(%{transcript: nil}), do: ""

  defp transcript_html(log) do
    accuracy_badge =
      if log.accuracy_score do
        pct = round(log.accuracy_score * 100)
        color = cond do
          pct >= 80 -> "#16a34a"
          pct >= 60 -> "#d97706"
          true      -> "#dc2626"
        end
        ~s(<div style="margin-top:8px;font-size:11px;color:#{color};font-weight:600;">Accuracy: #{pct}%</div>)
      else
        ""
      end

    """
    <tr>
      <td style="background:#ffffff;padding:20px 32px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;">
        <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;color:#f97316;text-transform:uppercase;margin-bottom:10px;">Field Recording Transcript</div>
        <div style="font-size:13px;line-height:1.7;color:#374151;background:#f9fafb;border-left:3px solid #f97316;padding:12px 16px;border-radius:0 4px 4px 0;font-style:italic;">&ldquo;#{escape(log.transcript)}&rdquo;</div>
        #{accuracy_badge}
      </td>
    </tr>
    #{divider()}
    """
  end

  # ---------------------------------------------------------------------------
  # Section renderers
  # ---------------------------------------------------------------------------

  defp section_html(_title, items, _fun) when items in [nil, []], do: ""

  defp section_html(title, items, render_fn) do
    rows = Enum.map_join(items, "", render_fn)

    """
    <tr>
      <td style="background:#ffffff;padding:20px 32px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;">
        <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;color:#f97316;text-transform:uppercase;margin-bottom:12px;">#{title}</div>
        #{rows}
      </td>
    </tr>
    #{divider()}
    """
  end

  defp progress_item(item) do
    pct = item["percentage_complete"]

    progress_bar =
      if pct do
        bar_color = cond do
          pct >= 80 -> "#16a34a"
          pct >= 50 -> "#f97316"
          true      -> "#dc2626"
        end
        ~s(<div style="margin-top:8px;"><div style="background:#e5e7eb;border-radius:4px;height:6px;width:100%;"><div style="background:#{bar_color};border-radius:4px;height:6px;width:#{pct}%;"></div></div><div style="font-size:11px;color:#{bar_color};font-weight:600;margin-top:4px;">#{pct}% complete</div></div>)
      else
        ""
      end

    """
    <div style="margin-bottom:12px;">
      <div style="font-size:13px;font-weight:600;color:#111827;">#{escape(item["description"])}</div>
      <div style="font-size:12px;color:#6b7280;margin-top:2px;">#{escape(item["location"])}</div>
      #{progress_bar}
    </div>
    """
  end

  defp equipment_item(item) do
    note = if item["note"] && item["note"] != "", do: " · #{escape(item["note"])}", else: ""

    """
    <div style="margin-bottom:10px;">
      <div style="font-size:13px;font-weight:600;color:#111827;">#{escape(item["item"])}</div>
      <div style="font-size:12px;color:#6b7280;margin-top:2px;">Status: <span style="font-weight:500;color:#374151;">#{escape(item["status"])}</span>#{note}</div>
    </div>
    """
  end

  defp materials_item(item) do
    label = item["item"] || item["material"] || inspect(item)
    qty   = item["quantity"] || item["qty"]
    qty_line = if qty, do: ~s(<div style="font-size:12px;color:#6b7280;">Qty: #{escape(to_string(qty))}</div>), else: ""

    """
    <div style="margin-bottom:10px;">
      <div style="font-size:13px;font-weight:600;color:#111827;">#{escape(label)}</div>
      #{qty_line}
    </div>
    """
  end

  defp delays_item(item) do
    label    = item["description"] || item["reason"] || inspect(item)
    duration = item["duration"]
    dur_line = if duration, do: ~s(<div style="font-size:12px;color:#b91c1c;margin-top:2px;">Duration: #{escape(to_string(duration))}</div>), else: ""

    """
    <div style="margin-bottom:10px;background:#fef2f2;border-left:3px solid #ef4444;padding:10px 12px;border-radius:0 4px 4px 0;">
      <div style="font-size:13px;font-weight:600;color:#991b1b;">#{escape(label)}</div>
      #{dur_line}
    </div>
    """
  end

  defp safety_item(item) do
    label = item["observation"] || item["note"] || item["description"] || inspect(item)

    """
    <div style="margin-bottom:10px;background:#fefce8;border-left:3px solid #eab308;padding:10px 12px;border-radius:0 4px 4px 0;">
      <div style="font-size:13px;font-weight:600;color:#854d0e;">#{escape(label)}</div>
    </div>
    """
  end

  defp labor_table_html(items) when items in [nil, []], do: ""

  defp labor_table_html(labor) do
    rows =
      Enum.map_join(labor, "", fn item ->
        sub = item["subcontractor"]
        sub_cell = if sub && sub != "", do: escape(sub), else: "—"

        """
        <tr>
          <td style="padding:8px 12px 8px 0;font-size:13px;color:#374151;border-bottom:1px solid #f3f4f6;">#{escape(item["trade"])}</td>
          <td style="padding:8px 12px 8px 0;font-size:13px;color:#374151;border-bottom:1px solid #f3f4f6;">#{escape(item["crew"])}</td>
          <td style="padding:8px 12px 8px 0;font-size:13px;color:#374151;text-align:center;border-bottom:1px solid #f3f4f6;">#{escape(to_string(item["headcount"]))}</td>
          <td style="padding:8px 12px 8px 0;font-size:13px;color:#374151;text-align:center;border-bottom:1px solid #f3f4f6;">#{escape(to_string(item["hours"]))}h</td>
          <td style="padding:8px 0;font-size:13px;color:#374151;border-bottom:1px solid #f3f4f6;">#{sub_cell}</td>
        </tr>
        """
      end)

    """
    <tr>
      <td style="background:#ffffff;padding:20px 32px;border-left:1px solid #e5e7eb;border-right:1px solid #e5e7eb;">
        <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;color:#f97316;text-transform:uppercase;margin-bottom:12px;">Labor</div>
        <table width="100%" cellpadding="0" cellspacing="0">
          <tr>
            <th style="text-align:left;font-size:10px;font-weight:600;color:#9ca3af;text-transform:uppercase;letter-spacing:0.5px;padding-bottom:8px;">Trade</th>
            <th style="text-align:left;font-size:10px;font-weight:600;color:#9ca3af;text-transform:uppercase;letter-spacing:0.5px;padding-bottom:8px;">Crew</th>
            <th style="text-align:center;font-size:10px;font-weight:600;color:#9ca3af;text-transform:uppercase;letter-spacing:0.5px;padding-bottom:8px;">People</th>
            <th style="text-align:center;font-size:10px;font-weight:600;color:#9ca3af;text-transform:uppercase;letter-spacing:0.5px;padding-bottom:8px;">Hours</th>
            <th style="text-align:left;font-size:10px;font-weight:600;color:#9ca3af;text-transform:uppercase;letter-spacing:0.5px;padding-bottom:8px;">Subcontractor</th>
          </tr>
          #{rows}
        </table>
      </td>
    </tr>
    #{divider()}
    """
  end

  # ---------------------------------------------------------------------------
  # Plain-text fallback
  # ---------------------------------------------------------------------------

  defp report_text(log) do
    """
    Daily Site Log — #{log.project.name} (#{log.project.code})
    Date: #{format_date(log.date)}
    Location: #{log.project.address || "—"}
    Submitted by: #{log.foreman.name}
    #{if log.weather, do: "Weather: #{log.weather}\n", else: ""}
    TRANSCRIPT
    #{log.transcript || "—"}

    PROGRESS
    #{Enum.map_join(log.progress, "\n", &"- #{&1["description"]} (#{&1["location"]}) — #{&1["percentage_complete"]}%")}

    LABOR
    #{Enum.map_join(log.labor, "\n", &"- #{&1["trade"]} · #{&1["crew"]} · #{&1["headcount"]} people · #{&1["hours"]}h")}

    EQUIPMENT
    #{Enum.map_join(log.equipment, "\n", &"- #{&1["item"]} [#{&1["status"]}]")}

    The full PDF report is attached.
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_date(%Date{} = d) do
    month =
      ~w(January February March April May June July August September October November December)
      |> Enum.at(d.month - 1)

    "#{month} #{d.day}, #{d.year}"
  end

  defp escape(nil), do: ""

  defp escape(str) do
    str
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
