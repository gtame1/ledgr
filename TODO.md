# Ledgr — TODO

## Casa Tame

### Features
- [x] **Split payment** — When recording an expense, allow splitting across multiple payment accounts. Dynamic add/remove rows UI; backend creates one debit + N credit journal lines. Splits stored in `expense_splits` table.
- [x] **Receipt / document storage** — Attach JPG, PNG, PDF, or WebP receipts to an expense. Files stored on disk (`priv/static/uploads/receipts/` in dev, `$UPLOAD_VOLUME/uploads/receipts/` in prod). Metadata tracked in `expense_attachments` table. Shown/managed on the expense detail page.

### Features (pending)
- [ ] **Refunded expenses** — Record when an expense is partially or fully refunded. UI to mark a refund, backend creates a reverse journal entry (credit the expense account, debit the payment account). Show refund status/amount on expense detail page.

### Cleanup
- [x] **Remove debug logging from income controller** — Done.

---

## Aumenta Mi Pensión

### Bot four-axis migration — revisit when bot ships

The bot service is migrating from a flat `funnel_stage` enum on
`conversations` to a four-axis state model (`funnel_stage`,
`qualification_verdict`, `escalation_status`, `engagement_health`).
Today Ledgr mirrors those four axes on the operator-owned
`conversation_crm` overlay. Once the bot's columns land on
`conversations`, do this:

- [ ] **Schema sync.** Add the four bot columns to
  `Ledgr.Domains.AumentaMiPension.Conversations.Conversation` (no
  Ledgr migration — bot owns the table).
- [ ] **Pick a reconciliation model.** Either:
  - **Bot wins, overlay dies** — drop the four axes from
    `conversation_crm`; show reads `conv.funnel_stage` etc. directly.
    Keep `contact_stage` / `sales_stage` (they're independent).
  - **Bot canonical, overlay is override** — both columns exist; UI
    shows bot value when overlay is null; add a "revert to bot"
    affordance.
- [ ] **Retire / extend `FunnelStageAudit`.** Drop it if the bot's
  `funnel_stage` column is gone/renamed, or generalize it into a
  shared `EnumAudit` that watches all four new columns (and future
  axes for other domains).
- [ ] **Vocabulary reconciliation.** Compare the bot's axis values
  against what's in `CrmEntry` today; align where they diverge.
- [ ] **Index filter follow-through.** `/conversations` filters on
  `conversations.funnel_stage` — if the bot renames/restructures the
  column, update the controller, the dropdown, and `funnel_stages/0`.
- [ ] **Backfill script.** Project the existing flat funnel values on
  the 458 historical conversations onto the new axes; review the
  before/after counts side by side before running.
- [ ] **Convert this checklist to GH issues** once the bot has a
  ship date, so each item has a home.

### Funnel stage drift (long-term)

- [ ] **Periodic drift re-check.** `FunnelStageAudit` runs once on
  boot. If the bot ships mid-day, drift won't surface until restart.
  Add a `:timer.hours(6)` re-audit (or move to Oban).
- [ ] **Surface drift in the admin UI.** Banner on
  `/app/aumenta-mi-pension/conversations` when `unknown_in_db` is
  non-empty — catches developers who don't tail logs.

### CRM card — when there's time

- [ ] **Optional `notes` field** on `conversation_crm` for free-text
  operator annotations. Currently only structured enums are
  capturable.
- [ ] **Keyboard shortcut for prev/next** (e.g. `[` / `]`) on the
  conversation show page.

### Schema field rename (bot-coordinated)

- [ ] **Rename `checkup_responses.birth_before_july_1997` →
  `cotized_before_july_1997`.** The column name is misleading — the
  semantic is "started contributing to IMSS before July 1997", not
  literal birth date. Needs a bot-side migration first, then sync the
  Ecto schema in
  `lib/ledgr/domains/aumenta_mi_pension/checkup_responses/checkup_response.ex`
  and update the template at
  `lib/ledgr_web/domains/aumenta_mi_pension/checkup_html/show.html.heex`.
  Display label already updated to "¿Cotizado antes de 7/1997?".

---

## Cross-domain / Core

*(nothing yet)*

---

## Infrastructure / DevOps

*(nothing yet)*
