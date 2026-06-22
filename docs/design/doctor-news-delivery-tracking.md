# Doctor News Blast — delivery tracking (backend ask)

**Status:** proposed — Hello Doctor backend change. The ledgr UI can consume it once it exists.
**Audience:** whoever owns the Hello Doctor bot service.

## Problem

The blast endpoint reports `sent` / `failed`, but `sent` only means **WhatsApp (Meta) accepted the API request** — not that the message reached the handset. Marketing-category templates (like `noticia_doctores`) are frequently dropped *after* acceptance, and that outcome arrives asynchronously via a delivery-status webhook.

Observed in prod (2026-06-22, a 1-recipient test):

```
Cloud API template noticia_doctores sent to 17135044274 (id=wamid.HBgL...274)
doctor_news: blast complete total=1 sent=1 failed=0          ← reported success

# ~7s later, via webhook:
Outbound wamid.HBgL...274 failed delivery (Meta):
  code 131049 "This message was not delivered to maintain healthy ecosystem engagement."
```

So the operator saw "sent=1" but the doctor never received it. `sent` ≠ `delivered`.
The real status (`131049`) exists only in CloudWatch, invisible to the operator.

## What we want

A way for ledgr to show **true per-blast delivery outcomes** (delivered / read / failed-with-reason), not just acceptance.

This requires the bot to (a) persist the `wamid` ↔ blast/doctor mapping at send time, (b) record the delivery-status webhooks Meta sends for those `wamid`s, and (c) expose the rollup.

### Suggested shape

1. **At send time**, persist per recipient: `blast_id` (generate one per blast), `doctor_id`, `wamid`, `phone`, initial status `accepted`.
   - Return `blast_id` in the `broadcast-news` response so ledgr can poll/link it:
     ```jsonc
     { "blast_id": "blast_2026...", "total": 1, "sent": 1, "failed": 0, ... }
     ```
2. **On delivery webhook**, update the row by `wamid`: `sent → delivered → read`, or `failed` with the Meta error `code`/`title` (e.g. `131049`).
3. **New endpoint** `GET /admin/doctors/broadcast-news/{blast_id}` (same `X-API-Key`):
   ```jsonc
   {
     "blast_id": "blast_2026...",
     "created_at": "2026-06-22T20:31:12Z",
     "total": 1,
     "counts": { "accepted": 0, "delivered": 0, "read": 0, "failed": 1 },
     "recipients": [
       { "doctor_id": "03f3b382-...", "phone_last4": "4274",
         "status": "failed", "error_code": 131049,
         "error_title": "This message was not delivered to maintain healthy ecosystem engagement." }
     ]
   }
   ```
   (Keep phones redacted to last-4, consistent with the dry-run preview.)

### ledgr side (once the above exists)

- `broadcast_doctor_news/3` already returns the raw body — surface `blast_id`.
- After a send, store `blast_id` and poll `GET …/{blast_id}` (or offer a "Check delivery" button), rendering the `counts` + per-recipient failures with the Meta reason. Small additive change to `DoctorNewsController` + the result panel.

## Notes / open questions for the backend owner

1. **131049 is expected for marketing templates** — it's Meta's per-user marketing-message throttle, not a code bug. Worth confirming the template's category; if some of these blasts are transactional in nature, a **utility**-category template would be throttled far less. Is `noticia_doctores` marketing or utility?
2. Retry policy on `131049`? (Generally not retriable immediately — Meta is rate-limiting that user.) Recommend *not* auto-retrying; surface it instead.
3. Retention: how long to keep per-recipient delivery rows? (A blast is one-shot; 30–90 days is plenty for operator follow-up.)
4. Is a poll endpoint acceptable, or would you rather push status to ledgr? Polling is simplest for a one-shot blast.

## Interim (no backend change)

Until this lands, ledgr's send result has been reworded to say **"Accepted by WhatsApp for N doctor(s)"** with a note that acceptance ≠ delivery — so operators don't read `sent` as `delivered`. True delivery still has to be checked in CloudWatch (`app.services.doctor_news` / webhook `failed delivery` lines) or with the doctor directly.
