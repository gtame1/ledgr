# Reporting architecture

**Status:** proposed
**Date:** 2026-08-01
**Scope:** Hello Doctor **only**. Every other Ledgr domain (Aumenta Mi Pensión,
Casa Tame, Mr Munch Me, Volume Studio, Viaxe, Ledgr HQ) is out of scope for
this project, including their dashboards. The pattern should generalise later,
but proving it on one domain comes first.

## The problem

Three symptoms, one cause.

1. **Slow.** Every metric change is an edit to a 500–1,500 line Elixir module,
   a push, and a Render deploy (with `clearCache` when HEEx is touched).
2. **Opaque.** The SQL that produced a number is invisible from the page. You
   cannot audit a figure without opening the repo.
3. **Wrong, repeatedly.** Not occasionally — systematically, and always in the
   same way.

Symptom 3 is the one that matters. A partial list of measurement bugs found so
far, each of which had to be rediscovered independently in more than one report:

| Rule | What goes wrong when it's forgotten |
|---|---|
| Free/comped consults are `payment_status = 'confirmed'` with `payment_amount = 0` | Paid-consult counts and revenue are inflated |
| MX-local dates compared against UTC-stored naive timestamps | Every dashboard undercounts the current day |
| `conversations.funnel_stage` goes stale after consultation handoff | Paid / completed / doctor-matched KPIs are mismeasured |
| Test accounts must be excluded via `NOT EXISTS` (`NOT IN` drops NULLs) | Test traffic silently counted as real |
| Genuine "direct" ⟺ `targeted_doctor_id IS NOT NULL`, not `tenant` alone | Direct vs MVP attribution is wrong |
| Doctor share is the doctor's own `consultation_fee_mxn`, not a flat 100 | Payouts and margin are wrong |

**None of these is a tooling problem.** Switching to Metabase, or to any other
BI tool, preserves every one of them and removes the ability to see when one has
been violated. The business rules live in analysts' heads instead of in the
data, so they must be re-derived — correctly — by every author of every query,
forever.

Fix that first. Then the choice of surface is easy and reversible.

## Decision: no Metabase

Audience for the next quarter is a single reader. Metabase's value is
non-technical self-serve, which is not currently needed, and its cost is a
second home for metric definitions that will drift from the GL. The local
container can stay for casual poking; it is not part of this architecture.

If a teammate later needs drag-and-drop self-serve, host Metabase then, pointed
at `analytics.*` — where it cannot get the rules wrong.

## Architecture

Four layers, each independently useful, built in order.

```
┌──────────────────────────────────────────────────────────┐
│ 4. Dashboard consolidation — one definition per metric   │
├──────────────────────────────────────────────────────────┤
│ 3. Ledgr report surface — versioned .sql + "show query"  │
├──────────────────────────────────────────────────────────┤
│ 2. Reconciliation checks — do the numbers tie to the GL? │
├──────────────────────────────────────────────────────────┤
│ 1. Semantic layer — analytics.* views, rules applied     │
└──────────────────────────────────────────────────────────┘
                          ▲
              Claude Code + Neon MCP reads here
```

Ad-hoc exploration is not a layer. It is Claude Code querying layer 1 directly.

---

### Layer 1 — Semantic layer (`analytics` schema)

A set of plain SQL views in a new `analytics` schema on the Hello Doctor
database, shipped as Ledgr migrations under
`priv/repos/hello_doctor/migrations`. The bot owns the `public` base tables;
Ledgr owns everything in `analytics`, so there is no ownership conflict and no
coordination with the bot's migration tooling.

**Views, not materialized views.** Always fresh, no refresh job, no staleness
class of bug. Revisit only if a specific view measurably hurts.

**Design rules:**

- Every rule from the table above is applied *inside* the view, exposed as a
  plain column. No consumer may re-derive one.
- Dates are exposed pre-converted: `created_at_mx date` alongside the raw
  `created_at`. Timezone bugs become impossible to write.
- Booleans over enums-with-caveats: `is_paid`, `is_comped`, `is_test`,
  `is_direct`. The subtlety is spent once, here.
- Rules are **ported from the existing Elixir modules, not reinvented** —
  `TestAccounts`, `ConsultationAccounting`, `DashboardMetrics` are the current
  source of truth and must be read before each view is written.
- Additive only. Existing dashboards keep working; they migrate one at a time.

**Proposed objects:**

| View | Grain | Key derived columns |
|---|---|---|
| `analytics.fct_consultation` | one consultation | `is_paid`, `is_comped`, `is_corporate`, `is_direct`, `is_test`, `gross_mxn`, `doctor_share_mxn`, `hd_commission_mxn`, `created_at_mx`, `completed_at_mx` |
| `analytics.fct_payment` | one Stripe payment | `net_mxn`, `stripe_fee_mxn`, `refunded_mxn`, `is_test`, `paid_at_mx` |
| `analytics.fct_conversation` | one conversation | `outcome` (derived from `consultations.status` + payments, **never** `funnel_stage`), `is_test`, `created_at_mx` |
| `analytics.dim_doctor` | one doctor | `is_active`, `is_verified`, `consultation_fee_mxn`, `onboarded_via` |
| `analytics.dim_patient` | one patient | `is_test`, `first_consult_at_mx`, `lifetime_consults`, `segment` |

Caveat worth stating up front: `conversations` and `messages` are hard-deleted
by the bot, so `fct_conversation` is **not** a stable historical series. The
view should carry that warning in a `COMMENT ON VIEW`, which surfaces in every
introspection tool including mine.

**One table, not a view: `analytics_daily_snapshot`.**

Ledgr-owned, written once a day, never touched by the bot. It stores the
day's headline counts as computed from the views above.

This exists to solve the deletion problem, not to serve a dashboard. Because
the bot hard-deletes conversations and messages, historical counts today are
retroactively unreproducible — last month's number changes depending on when
you ask. A snapshot stops that bleeding from the day it ships, which makes it
the one piece of this design with a **clock running against it**: every day it
does not exist is a day of history permanently lost.

Writing it needs a scheduled job. Follow the existing pattern — a supervised
GenServer on a `:timer.hours(24)` loop, started conditionally in
`application.ex`, as `BillingSyncWorker`, `ExchangeRateWorker`,
`PatientSegmentsWorker` and `ConsultationPayoutsWorker` all do. Ledgr has **no
Oban**.

**Documentation is not optional here.** `COMMENT ON COLUMN` for every derived
column, stating the rule. This is what lets me — or a future teammate — write
correct SQL without reading the Elixir.

---

### Layer 2 — Reconciliation checks

The differentiator no BI stack has: Hello Doctor's general ledger
(`journal_entries`, `journal_lines`, `accounts`) lives in the *same database*
as the operational tables. Reported figures can be proven against double-entry
accounting in pure SQL.

**Convention: a check is a view that returns zero rows when healthy.**

```
analytics.check_revenue_ties_to_gl      -- monthly 4000 balance vs fct_consultation
analytics.check_doctor_payable_ties     -- 2000 balance vs unpaid doctor_share
analytics.check_payments_linked         -- confirmed consults with no stripe_payment
analytics.check_no_orphan_payouts       -- payouts without a consultation
```

Each row returned is a discrepancy, with enough columns to act on it. A single
runner selects from every `check_*` view and reports anything non-empty,
exposed as `mix ledgr.check`.

Checks are run on demand, and surfaced on the layer-3 report pages as a health
banner. Nothing pushes them anywhere — see *Explicitly out of scope*.

This is what makes numbers trustworthy. Not seeing the SQL — *proving it ties
to the ledger*. It also converts a whole class of silent drift (the kind behind
the corporate-consult gap and the mis-set doctor shares) into a same-day alert.

---

### Layer 3 — Ledgr report surface

Queries become content instead of code.

- SQL moves from Elixir heredocs into versioned files:
  `priv/reports/hello_doctor/<slug>.sql`, with a small frontmatter header
  (title, description, params, viz type).
- A generic runner loads, parameterises, and executes them; a generic renderer
  handles table / timeseries / KPI-row output.
- **Every rendered metric gets a "show query" disclosure** — one click reveals
  the exact SQL and the timestamp it ran. Trust problem solved directly.
- Reports are declared in a registry module, the way `Experiments` already
  declares experiments. That pattern works; extend it rather than invent one.

Adding a report becomes: write one `.sql` file, add one registry line. A change
becomes a one-line diff instead of surgery on `dashboard_metrics.ex`.

**Deferred:** an in-app SQL console with saved queries in a Ledgr table, giving
zero-deploy edits. Worth building only if the deploy loop still hurts once the
diff is three lines. Do not build it speculatively — it carries real auth and
read-only-role obligations for a problem layers 1–3 may already have solved.

---

### Layer 4 — Dashboard consolidation

**Scope fence: Hello Doctor only.** Aumenta Mi Pensión, Casa Tame, Mr Munch Me,
Volume Studio, Viaxe and Ledgr HQ are explicitly untouched. Their dashboards
almost certainly have the same disease (the MX-timezone bug is known to affect
AMP), but curing one domain properly and proving the pattern beats half-curing
six. The shared `ReportController` GL reports — balance sheet, P&L, cash flow —
are also out of scope: they read the ledger directly and are not affected.

#### This layer is not optional garnish

Layer 1 creates a *correct* definition of "paid consult." If the existing pages
keep computing their own, `analytics.*` becomes **a fourth source of truth
rather than a replacement for three** — strictly worse than doing nothing,
because now the disagreements are between systems instead of within one.

The measured duplication in `lib/ledgr/domains/hello_doctor/` today:

| Business rule | Modules deriving it independently |
|---|---|
| `payment_amount` (the free-consult rule) | 15 |
| `consultation_fee_mxn` (doctor share) | 10 |
| `America/Mexico_City` (the timezone fix) | 9 |
| `TestAccounts` exclusion | 8 |
| `funnel_stage` (known unreliable) | 5 |
| `targeted_doctor_id` (direct vs mvp) | **1** |

That last row is a finding, not a success. If only `dashboard_metrics.ex` knows
the genuine direct-vs-mvp rule, every other page reporting on "direct" derives
it some other way — most likely from `tenant` alone, which is known wrong.
**Audit this specifically.**

#### Method

Interleaves with layer 3 rather than strictly following it: each page migrates
to `.sql` files and to `analytics.*` in the same move.

1. **Metric census.** For every HD page, list the metrics it displays and the
   module + function that computes each. Publish the table in this repo.
2. **Find the disagreements.** Where two pages show the same metric from
   different modules, compute both against production and record the delta.
   Expect non-zero deltas; they are the point of the exercise.
3. **Converge.** Rewrite each page's query against `analytics.*`.
4. **Delete.** The old derivation comes out in the same commit.

**The discipline that makes this work: a page is not migrated until its old
derivation is deleted.** Leaving both means the duplication count never drops
and the next author picks the wrong one. No "migrate now, clean up later."

#### Page inventory and suspected overlap

| Page | Computed by | Consolidation note |
|---|---|---|
| Dashboard | `dashboard_metrics.ex` (1,500 LOC) | Overlaps Acquisition and Unit Economics on funnel + volume KPIs |
| Acquisition | `acquisition_metrics.ex` (847) | Overlaps Dashboard; uses `funnel_stage` |
| Unit Economics | `lifecycle_metrics.ex` (547) | Overlaps both above on paid-consult and revenue counts |
| Payout Report | `monthly_report.ex` (891) | Overlaps Doctor Payouts on doctor money |
| Doctor Payouts | `doctor_payouts.ex` | Same |
| Experiments | `experiments.ex` (518) | Per-arm readouts re-derive paid/completed |
| NPS, Reviews, Triage, Specialties | small modules | Low overlap; migrate last |
| Conversations, Consultations, Doctors, Patients, Payments, Corporate | list/detail views | Operational, not analytical — leave as-is |

Roughly 4,300 LOC of analytics logic across the top five. The goal is not to
delete all of it — much is legitimate presentation — but every *rule* in it
should end up expressed once, in a view.

#### Expect the numbers to change

Migrating a page to correct definitions will move figures you have been
reading for months. That is success, not regression, but it must be handled
deliberately:

- Record the before/after for every metric whose value changes.
- Write down *why* it changed (which rule was previously missing).
- Keep that log in the repo. When a number looks wrong in three months, the
  first question will be "did we change this?" — and there should be an answer.

---

## Why this order

Layer 1 pays for itself immediately even if nothing else is built: it makes
ad-hoc Claude Code queries correct by construction, which is the fastest and
most-used path today. Layer 2 makes the numbers provable. Layer 3 makes them
shareable and fast to change. Layer 4 makes layer 1 *true* — until the pages
read from the views, the old definitions are still the ones you look at every
morning.

Layers 1–3 are each shippable alone and none blocks reverting the ones above
it. Layer 4 is the exception: it is not optional. Shipping layer 1 without
eventually doing layer 4 leaves the codebase with more definitions of "paid
consult" than it started with.

## Explicitly out of scope

**No push notifications.** No emailed digest, no WhatsApp alert, no scheduled
narrative agent. Considered and cut as premature: it required a mail provider
account, adapter config Ledgr does not have (`Ledgr.Mailer` is untouched
generator boilerplate — no production adapter, no `Mailer.deliver` call
anywhere), a worker, and a delivery page, all to serve a single reader who is
already in the app daily.

Reporting here is **pull, not push**. Open a page; the numbers are current.

Revisit only when a concrete need appears — e.g. a reconciliation check that
must be seen the same day it breaks. Note that the two components most likely
to be wanted then already exist and stay available: `Ledgr.Mailer` (needs only
a provider and one config line) and `Ledgr.Notifications.CallMeBot` (WhatsApp,
needs only `CALLMEBOT_API_KEY`).

**Deferred, not cut:** the in-app SQL console (see layer 3).

## Open questions

- Does the read-only `metabase_ro` role need `USAGE` on `analytics`? (Yes, if
  the local container is kept for exploration.)
- Do any views need materializing for the monthly report's date ranges? Measure
  before assuming.
- What exactly belongs in `analytics_daily_snapshot`? Err toward more columns —
  a column not captured today cannot be backfilled once the bot deletes the
  underlying rows.
