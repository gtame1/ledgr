defmodule Ledgr.Repos.MrMunchMe.Migrations.BackfillProductVariants do
  use Ecto.Migration

  def up do
    # For every product that doesn't yet have a variant, create one variant that
    # carries the product's own name, sku, and price_cents.  This preserves
    # all existing data: every product gets exactly one variant so the system
    # continues to work identically while Phase 3 wires up the application layer.
    execute("""
    INSERT INTO product_variants (product_id, name, sku, price_cents, active, inserted_at, updated_at)
    SELECT
      p.id,
      p.name,
      p.sku,
      p.price_cents,
      p.active,
      NOW(),
      NOW()
    FROM products p
    WHERE NOT EXISTS (
      SELECT 1 FROM product_variants v WHERE v.product_id = p.id
    )
    """)

    # Backfill orders.variant_id where not already set.
    # Each product currently has exactly one variant, so the join is 1-to-1.
    execute("""
    UPDATE orders o
    SET variant_id = v.id
    FROM product_variants v
    WHERE v.product_id = o.product_id
      AND o.variant_id IS NULL
    """)

    # Backfill recipes.variant_id where not already set.
    execute("""
    UPDATE recipes r
    SET variant_id = v.id
    FROM product_variants v
    WHERE v.product_id = r.product_id
      AND r.variant_id IS NULL
    """)
  end

  def down do
    # Nullify the backfilled variant_id columns (safe rollback — the table stays)
    execute("UPDATE orders SET variant_id = NULL")
    execute("UPDATE recipes SET variant_id = NULL")
    execute("DELETE FROM product_variants")
  end
end
