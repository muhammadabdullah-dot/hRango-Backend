"""The look of every e-mail: one simple, accessible layout (works in Outlook, Gmail and phone apps), with the
company's name as the sender line. Every value is escaped; links are only ever ones the API built."""
from dataclasses import dataclass
from html import escape

BRAND = "hRango"
_PRIMARY = "#2563eb"


@dataclass
class Button:
    label: str
    url: str


def render(*, title: str, paragraphs: list[str], button: Button | None = None, after: list[str] | None = None,
           company_name: str | None = None) -> tuple[str, str]:
    """(html, text) for a message. Paragraphs are plain text (escaped here)."""
    signed = company_name or BRAND
    blocks = "".join(f'<p style="margin:0 0 16px">{escape(p)}</p>' for p in paragraphs)
    if button:
        blocks += (
            '<p style="margin:24px 0">'
            f'<a href="{escape(button.url, quote=True)}" style="background:{_PRIMARY};color:#ffffff;'
            'text-decoration:none;padding:12px 20px;border-radius:6px;display:inline-block;font-weight:600">'
            f"{escape(button.label)}</a></p>"
            '<p style="margin:0 0 16px;font-size:13px;color:#4b5563">If the button does not work, copy this link '
            f'into your browser:<br><span style="word-break:break-all">{escape(button.url)}</span></p>'
        )
    blocks += "".join(f'<p style="margin:0 0 16px;font-size:13px;color:#4b5563">{escape(p)}</p>' for p in after or [])
    html = (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>{escape(title)}</title></head>"
        '<body style="margin:0;padding:0;background:#f3f4f6">'
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6">'
        '<tr><td align="center" style="padding:24px 12px">'
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        'style="max-width:560px;background:#ffffff;border-radius:8px">'
        '<tr><td style="padding:28px 28px 8px;font-family:Arial,Helvetica,sans-serif;font-size:15px;'
        'line-height:1.55;color:#111827">'
        f'<h1 style="margin:0 0 20px;font-size:20px;line-height:1.3">{escape(title)}</h1>{blocks}'
        f'<p style="margin:24px 0 0">Regards,<br>{escape(signed)}</p>'
        "</td></tr>"
        '<tr><td style="padding:16px 28px 24px;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#6b7280">'
        f"Sent by {BRAND} on behalf of {escape(signed)}. This is an automatic message; replies are not read."
        "</td></tr></table></td></tr></table></body></html>"
    )
    text_parts = [title, "", *paragraphs]
    if button:
        text_parts += ["", f"{button.label}: {button.url}"]
    text_parts += ["", *(after or []), "", "Regards,", signed]
    return html, "\n".join(p for p in text_parts if p is not None).strip() + "\n"
