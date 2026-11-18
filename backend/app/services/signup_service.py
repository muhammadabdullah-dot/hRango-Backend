"""Self-service sign-up (roadmap 1.1): a visitor creates an organisation on a 14-day trial without staff.

1. The visitor gives the company name, their name and e-mail (and optionally a plan).
2. One transaction: the company with its defaults and roles, the Account Owner (no password yet), the
   customer record linked to the company, the trial subscription, and a one-time link.
3. An e-mail with the link: opening it proves the address and lets the owner choose a password
   (POST /api/auth/invite/accept, the same page as an invitation).

The answer is the same when the e-mail already has an account; that person gets an e-mail saying so
instead, so the page cannot be used to find out who uses hRango. Asking is limited per address and per
machine like signing in (realm "signup"). Needs e-mail (503 SIGNUP_UNAVAILABLE without it).
"""
import json
from datetime import UTC, datetime
from typing import Any

from app.core import login_throttle, mail
from app.core.config import settings
from app.core.db import Db
from app.core.default_roles import expanded as default_roles
from app.core.errors import AppError, invalid
from app.core.mail_templates import Button, render
from app.repos import auth_repo, platform_repo
from app.services.account_links_service import INVITE_DAYS, UNUSABLE_PASSWORD, _link, _new_token
from app.services.platform_service import TRIAL

ANSWER = "Check your e-mail: we have sent a link to finish setting up your account."


def public_plans(db: Db) -> list[dict[str, Any]]:
    return db.call("plat.usp_plan_public_list")


def sign_up(db: Db, f: dict[str, Any], ip_address: str | None) -> None:
    if not mail.enabled():
        raise AppError(503, "SIGNUP_UNAVAILABLE",
                       "Sign-up is not open on this server yet. Contact hRango to set up your organisation.")
    email = f["owner_email"].strip().lower()
    if settings.login_throttle:
        login_throttle.check(db, "signup", email, ip_address)
        login_throttle.record(db, "signup", email, ip_address, False)

    if auth_repo.login_get(db, email) is not None:
        _tell_existing_account(db, email)
        return

    plan_id = f.get("plan_id")
    if plan_id is not None and not any(int(p["id"]) == plan_id for p in public_plans(db)):
        raise invalid("Choose one of the plans on offer.", "planId")

    company_name = f["company_name"].strip()
    owner_name = f["owner_name"].strip()
    token, digest = _new_token()
    with db.transaction():
        company_id = db.call_one("org.usp_company_provision", name=company_name, currency=f.get("currency") or "PKR",
                                 timezone=f.get("timezone") or "Asia/Karachi")["company_id"]
        db.call("auth.usp_role_defaults_apply", company_id=company_id,
                roles=json.dumps(default_roles(), ensure_ascii=False))
        user_id = db.call_one("plat.usp_signup_owner_add", company_id=company_id, email=email, display_name=owner_name,
                              password_hash=UNUSABLE_PASSWORD)["user_id"]
        customer_name = db.call_one("plat.usp_customer_name_free", name=company_name)["name"]
        customer = platform_repo.add_customer(db, None, company_id, {
            "name": customer_name, "contact_name": owner_name, "contact_email": email,
            "contact_phone": f.get("contact_phone"), "country": f.get("country"), "notes": "Self-service sign-up"}, None)
        if plan_id is not None:
            today = datetime.now(UTC).date()
            platform_repo.save_subscription(db, None, None, {
                "customer_id": customer["id"], "plan_id": plan_id, "billing_cycle": "monthly", "status": "trial",
                "amount": None, "start_date": today, "renews_on": today + TRIAL}, None)
        db.call("auth.usp_user_token_issue", user_id=user_id, purpose="invite", token_hash=digest,
                minutes=INVITE_DAYS * 24 * 60)

    html, text = render(
        title=f"Finish setting up {company_name}",
        paragraphs=[f"Hello {owner_name},",
                    f"Thank you for choosing hRango. Your organisation {company_name} is ready, with a "
                    f"{TRIAL.days}-day trial.",
                    f"You sign in with this e-mail address: {email}. Choose your password to open it."],
        button=Button("Choose your password", _link("/accept-invite", token)),
        after=[f"The link is valid for {INVITE_DAYS} days and works once.",
               "If you did not sign up, ignore this e-mail and nothing more will happen."],
        company_name=company_name)
    mail.queue(db, kind="signup", to_address=email, to_name=owner_name, subject=f"Finish setting up {company_name} on hRango",
               body_html=html, body_text=text, company_id=company_id, actor_id=user_id)


def _tell_existing_account(db: Db, email: str) -> None:
    html, text = render(
        title="You already have an hRango account",
        paragraphs=["Someone tried to create a new hRango organisation with this e-mail address.",
                    "This address already signs in to hRango, so nothing was created."],
        button=Button("Sign in", f"{settings.app_public_url.rstrip('/')}/login"),
        after=["Forgot your password? Use \"Forgot password\" on the sign-in page.",
               "If this was not you, you can ignore this e-mail."])
    mail.queue(db, kind="signup_existing", to_address=email, subject="You already have an hRango account",
               body_html=html, body_text=text)
