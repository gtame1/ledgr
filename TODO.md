# Ledgr — TODO

## Casa Tame

### Features
- [x] **Split payment** — When recording an expense, allow splitting across multiple payment accounts. Dynamic add/remove rows UI; backend creates one debit + N credit journal lines. Splits stored in `expense_splits` table.
- [x] **Receipt / document storage** — Attach JPG, PNG, PDF, or WebP receipts to an expense. Files stored on disk (`priv/static/uploads/receipts/` in dev, `$UPLOAD_VOLUME/uploads/receipts/` in prod). Metadata tracked in `expense_attachments` table. Shown/managed on the expense detail page.

### Cleanup
- [x] **Remove debug logging from income controller** — Done.

---

## Cross-domain / Core

*(nothing yet)*

---

## Infrastructure / DevOps

*(nothing yet)*
