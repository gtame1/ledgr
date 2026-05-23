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

### Bot four-axis migration — in progress

The bot shipped the schema migration on 2026-05-23, adding
`qualification_verdict`, `escalation_status`, `engagement_health` to
`conversations` and starting to repurpose the existing `funnel_stage`
column with the new five-value vocabulary (intake / qualifying /
terminal / escalating / closed). Data migration is just starting —
most rows still hold the legacy `funnel_stage` vocabulary, and the
three new axes are mostly NULL.

Reconciliation choice: **overlay-as-override**. The bot is the
canonical writer; the operator's `conversation_crm` overlay wins on
display when set. Selecting "— usar valor del bot —" clears the
overlay and reveals the bot's value.

- [x] **Schema sync.** Added the three new fields to
  `Ledgr.Domains.AumentaMiPension.Conversations.Conversation`.
- [x] **Reconciliation model picked.** Overlay-as-override (above).
- [x] **CRM card UX updated.** Each axis select edits the overlay;
  bot's value shown as a caption below; yellow "Anulado por operador"
  badge + orange select border when the overlay overrides.
- [x] **Vocabulary reconciliation (in part).** Added the new funnel
  vocab (intake / qualifying / terminal / escalating / closed) to
  `Conversations.funnel_stages/0` and the `@funnel_labels` map.
- [ ] **Retire / extend `FunnelStageAudit`.** Currently still useful
  for `conversations.funnel_stage` (mixed vocab during transition).
  Should be generalized into a shared `EnumAudit` that also watches
  `qualification_verdict`, `escalation_status`, `engagement_health` —
  catching drift the moment the bot starts using a value we don't
  recognize. Worth doing before those axes get populated in volume.
- [ ] **Index filter follow-through.** The `/conversations` filter
  dropdown still only filters by the bot's `funnel_stage` column.
  Once the new axes have data, add per-axis filters (or at least a
  `qualification_verdict` filter — it's the most actionable for an
  asesor).
- [ ] **Backfill.** The 364 historical conversations still have the
  legacy `funnel_stage` vocabulary and `NULL` on the new three axes.
  Decide whether to leave them as-is (bot may eventually recompute)
  or write a one-time backfill script projecting legacy → new vocab.
- [ ] **Drop legacy scattered fields.** `qualifies`,
  `recommended_modalidad`, `agent_recommended`,
  `agent_declined_by_customer`, `resolved_without_agent` still exist
  on `conversations`. Bot plan was to subsume them; coordinate
  removal once the new axes are reliably populated.

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
