"""Public pages Google Play asks for: the privacy policy and how to delete an account.
Plain HTML, no scripts, no tracking. The text states what the server really does; if the
product changes, change it here and in docs/SECURITY.md."""
import html

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from ..deps import settings_of

router = APIRouter(tags=["legal"])

_STYLE = ("body{margin:0;font-family:system-ui,sans-serif;background:#FAF3EA;color:#1F2A37;"
          "line-height:1.5}.w{max-width:720px;margin:0 auto;padding:20px}h1{color:#0F2A47}"
          "h2{color:#0F2A47;margin-top:28px}li{margin:4px 0}.s{color:#6b7280;font-size:14px}")


def _page(title: str, body: str) -> HTMLResponse:
    doc = (f"<!doctype html><meta charset=utf-8><meta name=viewport "
           f"content='width=device-width,initial-scale=1'><title>{html.escape(title)}</title>"
           f"<style>{_STYLE}</style><div class=w>{body}</div>")
    return HTMLResponse(doc, headers={"Cache-Control": "public, max-age=3600"})


def _contact(request: Request) -> str:
    email = settings_of(request).contact_email
    return (f"<a href='mailto:{html.escape(email)}'>{html.escape(email)}</a>" if email
            else "the support contact given on the app's store page")


@router.get("/privacy", response_class=HTMLResponse)
def privacy(request: Request):
    return _page("Smriti Sathi privacy policy", f"""
<h1>Smriti Sathi: privacy policy</h1>
<p class=s>Smriti Sathi is a memory-games, reminders and care-coordination app for people with
memory difficulties, their families, caregivers and doctors. It is a support tool and not a
medical device: it does not diagnose, treat or monitor any condition, and its AI helper gives
general information only.</p>

<h2>What we collect, and why</h2>
<ul>
<li><b>Account:</b> your mobile number (to sign in with a one-time code; the server keeps a keyed
hash of it, not the plain number, except the last four digits shown to you), your name, your role
(patient, caregiver or doctor). Doctors also give a registration id.</li>
<li><b>Profile (patient):</b> date of birth, city, language, the starting game level a caregiver
sets, and an optional photo.</li>
<li><b>Memory games:</b> the result of each game played (game, level, how many were right, when).
Used for your progress and, if you allow it, shown to your caregiver and doctor.</li>
<li><b>Reminders and routines:</b> medicine, activity and appointment reminders you or your
caregiver or doctor add, and when you tick them off. Health-related, shared only with the people
you link.</li>
<li><b>Family contacts:</b> stored on your phone only, not on our server.</li>
<li><b>Messages:</b> text, photos and voice notes you send to your linked caregiver or doctor, kept
on the server so they appear on any phone you sign in on.</li>
<li><b>Location:</b> only when you press &ldquo;Are You Lost? Tell Your Loved Ones&rdquo;. Your
position is sent to our server and to the people you chose (the caregiver in the app, family by an
SMS link) while you share. We keep only the latest point, and delete it when you stop, when the
time ends (2 hours by default, 4 at most) or when you delete your account. Nothing is collected
when you are not sharing.</li>
<li><b>AI helper (&ldquo;Talk to Smriti&rdquo;):</b> only if you allow it. The questions you type
(and the last few lines of the conversation) are sent through our server to an AI provider to get an
answer. We do not store them. The conversation history is kept on your phone only.</li>
<li><b>Device and push:</b> a push token so notifications can reach your phone, and technical logs
without personal content. A security log records who accessed or changed what (ids only).</li>
</ul>

<h2>Who sees it</h2>
<ul>
<li>Only people you invite and who accept: your caregiver and doctor, and only the parts you
allowed. A doctor you ask for an opinion sees your question and nothing else about you.</li>
<li>Family you tick for live location receive a link while you share.</li>
<li>AI answers are produced by a third-party AI provider that receives the text you send to the
helper. We do not sell data, show ads or use it for advertising.</li>
<li>We share data when the law requires it.</li>
</ul>

<h2>Your choices and rights</h2>
<ul>
<li>Every kind of sharing is a separate consent you can change or withdraw at any time in
<b>Profile &rarr; Privacy</b>. Withdrawing stops that use at once.</li>
<li>See all the data held about you, and <b>erase your account and data</b>, in the same place.
You can also ask for deletion on <a href="/delete-account">the account deletion page</a>.</li>
<li>You may ask for correction or complain to the data protection authority. Contact:
{_contact(request)}.</li>
</ul>

<h2>Security and retention</h2>
<p>Data travels over HTTPS. The phone database is encrypted. Sign-in uses one-time codes and short-lived
tokens. We keep data while the account exists; when you erase the account the profile, game results,
reminders, messages and live location are deleted from the server. The security log keeps only the fact
that an erasure happened, with no personal details. Backups are overwritten within 30 days.</p>

<h2>Children</h2>
<p>Smriti Sathi is for adults and their care teams. It is not directed at children under 18.</p>

<h2>Reporting content</h2>
<p>You can report an AI answer or a message from inside the app (the flag icon, or press and hold a
message). Reports go to the operator for review.</p>

<h2>Changes</h2>
<p>If this policy changes we ask again for consent where needed. Questions: {_contact(request)}.</p>
""")


@router.get("/delete-account", response_class=HTMLResponse)
def delete_account(request: Request):
    return _page("Delete your Smriti Sathi account", f"""
<h1>Delete your Smriti Sathi account</h1>
<h2>In the app (immediate)</h2>
<ol>
<li>Open Smriti Sathi and sign in.</li>
<li>Go to <b>Profile &rarr; Privacy</b>.</li>
<li>Choose <b>Erase my data</b> and confirm.</li>
</ol>
<p>This deletes your account from this phone and from our server: profile, game results, reminders
and routines, messages, photos, voice notes and any live location. It cannot be undone. The security
log keeps only that an erasure took place.</p>
<h2>Without the app</h2>
<p>If you can no longer open the app, write to {_contact(request)} from or about the same mobile number,
saying that you want your Smriti Sathi account deleted. We confirm that it is you by sending a code to
that number, then delete the account within 30 days.</p>
<p class=s>Caregivers and doctors: deleting your own account removes you from your patients' care teams;
it does not delete the patients' data.</p>
<p><a href="/privacy">Privacy policy</a></p>
""")
