# Hello Doctor — metric census

**Status:** findings, 2026-08-01
**Layer 4, step 1** of [reporting-architecture.md](reporting-architecture.md).
**Method:** static read of `lib/ledgr/domains/hello_doctor/`, then each
competing definition measured against the production database (read-only).
**Measurement window:** consultations with `completed_at >= 2026-05-01`
(123 rows). Counts will move; the *disagreements* are the point.

---

## Headline: "paid consultation" has four definitions in production

Grepped from the modules, then counted:

| # | Predicate | Used by | Count |
|---|---|---|---|
| A | `payment_status IN ('paid','confirmed') AND payment_amount > 0` | **Dashboard** (`dashboard_metrics.ex` ×3) | **66** |
| B | `payment_status IN ('paid','confirmed')` | **Experiments** (`experiments.ex:401`), `dashboard_metrics.ex:218` | **121** |
| C | `payment_status IN ('paid','confirmed','refunded')` | **Unit Economics** (`lifecycle_metrics.ex:328`), `consultation_revenue.ex:90`, `consultation_payouts.ex:107`, both funnel exports | **123** |
| D | `... AND payment_amount >= 0` | `consultation_payouts.ex:117`, `doctor_payouts.ex:141` | — |

**The Dashboard says 66 paid consultations. Unit Economics says 123. Nearly
2×, for the same period, in the same app.**

Why, from the underlying distribution:

| `payment_status` | `payment_amount` | Consults | Sum MXN |
|---|---|---|---|
| confirmed | positive | 62 | 9,215 |
| confirmed | **zero** | **53** | 0 |
| paid | positive | 4 | 480 |
| confirmed | **null** | **2** | 0 |
| refunded | positive | 2 | 255 |

- **55 free/comped consults** (`confirmed` with zero or null amount) are counted
  as paid by definitions B and C. This is the known free-consult contamination,
  still live on two pages.
- **2 refunded consults ($255)** are counted as revenue by definition C — money
  returned to the customer, booked as income.
- Note definition B appears at `dashboard_metrics.ex:218` while definition A
  appears three times elsewhere in *the same module*. The Dashboard is
  internally inconsistent.

### Proposed canonical rule for `analytics.fct_consultation`

Not one boolean — the disagreement above is really three separate questions
being collapsed into one:

```
is_collected  -- payment_status IN ('paid','confirmed','refunded')
is_paid       -- payment_status IN ('paid','confirmed') AND payment_amount > 0
is_comped     -- payment_status IN ('paid','confirmed')
                 AND COALESCE(payment_amount, 0) = 0
is_refunded   -- payment_status = 'refunded'
gross_mxn     -- COALESCE(payment_amount, 0), 0 when refunded
```

Every current definition is then expressible without a `WHERE` clause anyone
has to remember, and "should refunds count?" becomes a visible choice rather
than an accident of which module a page happened to call.

---

## Second finding: test-account exclusion diverges (latent, not live)

`TestAccounts` is documented as the single source of truth and covers **3 test
phones + 1 test patient id**, via a `NOT EXISTS` helper. Eight modules use it.

`monthly_report.ex` does not. It hardcodes its own two constants
(`@test_patient_id`, `@test_doctor_id` at lines 48–49) and **never excludes the
three test phones**.

Measured impact today: **zero**. All four test-phone consultations happen to
also involve the test doctor, so the payout report's `@test_doctor_id`
exclusion catches them by coincidence:

| Phone | Consults | Caught by test-doctor filter |
|---|---|---|
| 5215512950400 | 2 | yes |
| 5215536713304 | 1 | yes |
| 5215543408539 | 1 | yes |

This is correct-by-luck. The moment someone QAs against a real doctor, test
traffic enters the doctor payout report — a report that moves money. Fix by
switching `monthly_report.ex` to `TestAccounts.not_test_patient_sql/1`.

---

## Third finding: doctor-share logic is duplicated but *not* divergent

Two independent implementations of the tenant-aware doctor share:

- `consultation_accounting.ex:68` (and `:88` for the SQL form)
- `monthly_report.ex:322-324`, with `@doctor_share_mxn 100.0` at line 36 as the
  non-direct fallback

Both read: *direct tenant with a configured `consultation_fee_mxn` → that fee;
otherwise flat 100.* They agree today. The `$3` parameter in `monthly_report`
is only the fallback, not a flat override — checked, because the hardcoded
`100.0` looks like the known "never hardcode 100" bug and **is not**.

Risk is drift, not present error. Collapse into one expression in
`fct_consultation.doctor_share_mxn`.

### Audit item — RESOLVED 2026-08-01

Both implementations key on `conversations.tenant = 'direct'`, while
`dashboard_metrics.ex` alone uses `targeted_doctor_id IS NOT NULL` — the rule
recorded as the genuine test for a direct consult. Measured across all
completed consultations:

| `tenant` | targeted? | Consults | Share by `tenant` | Share by `targeted` |
|---|---|---|---|---|
| mvp | no | 128 | 12,800 | 12,800 |
| direct | yes | 4 | 650 | 650 |
| mvp | **yes** | 1 | 100 | 100 |

**The two rules agree on every peso today** — 13,550 either way. After the
2026-06-28 backfill, `tenant` and `targeted_doctor_id` are aligned except for a
single `mvp`-but-targeted consultation, and that doctor has no configured
`consultation_fee_mxn`, so both rules fall through to the same 100 fallback.

Decision: encode **`is_direct = targeted_doctor_id IS NOT NULL`** (the genuine
semantic), and keep `tenant` as a separate descriptive column rather than
folding it in. Add a layer-2 check for the only case where the two can move
money apart:

```
analytics.check_direct_attribution_agrees
  -- rows where tenant='direct' <> targeted_doctor_id IS NOT NULL
  --   AND the doctor has a custom consultation_fee_mxn
```

Empty today. It fires the day the two drift in a way that changes a payout.

---

## Page → module inventory

| Page | Route | Computed by | Notes |
|---|---|---|---|
| Dashboard | `/` (shared `ReportController.dashboard`) | `dashboard_metrics.ex` (1,500 LOC) | 22 public functions; definition A ×3 **and** B ×1 |
| Acquisition | `/acquisition` | `acquisition_metrics.ex` (847) | uses `funnel_stage` (known unreliable) |
| Unit Economics | `/unit-economics` | `lifecycle_metrics.ex` (547) | definition C |
| Payout Report | `/reports/monthly` | `monthly_report.ex` (891) | own test-account constants |
| Doctor Payouts | `/doctor-payouts` | `doctor_payouts.ex` | definition D |
| Experiments | `/experiments` | `experiments.ex` (518) | definition B |
| NPS | `/nps` | `nps.ex` | low overlap |
| Triage | `/triage` | `bot_admin.ex` | operational, not analytical |
| Corporate | `/corporate` | `corporate_usage.ex` | — |
| Conversations, Consultations, Doctors, Patients, Payments | list/detail | various | operational — out of scope |

Not analytics but sharing the same rules, so they must migrate too:
`consultation_funnel_export.ex`, `conversation_funnel_export.ex`,
`consultation_revenue.ex`, `patient_segments.ex`.

### Rule duplication counts

| Rule | Modules deriving it independently |
|---|---|
| `payment_amount` | 15 |
| `consultation_fee_mxn` | 10 |
| `America/Mexico_City` | 9 |
| `TestAccounts` | 8 |
| `funnel_stage` | 5 |
| `targeted_doctor_id` | 1 |

---

## Verified *not* a problem

Recorded so they aren't re-investigated:

- **`DashboardController` dead code** — previously flagged; the dead `index/2`
  and its `dashboard_html/` directory have been deleted. Only `update_fx_rate`
  and `sync_costs` remain.
- **Doctor share hardcoded at 100** — looks like the known bug, is actually a
  correct fallback in both implementations (above).
- **Balance Sheet / P&L / Cash Flow** — read the GL directly via the shared
  `ReportController`; unaffected by any of this.

---

## Next

1. ~~Resolve the `tenant` vs `targeted_doctor_id` audit item~~ — done, above.
2. Build `analytics.fct_consultation` with the four-boolean split.
3. Migrate pages one at a time, deleting each old derivation in the same
   commit, logging every number that moves.

Order matters for step 3: **Dashboard last.** Its 66 is the closest to correct
of the three, so migrating it first would produce the smallest visible change
and the least evidence that the migration works. Start with Unit Economics,
where the number should move most.
