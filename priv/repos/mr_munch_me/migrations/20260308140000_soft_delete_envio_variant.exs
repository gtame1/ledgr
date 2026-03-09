defmodule Ledgr.Repos.MrMunchMe.Migrations.SoftDeleteEnvioVariant do
  use Ecto.Migration

  def up do
    # The ENVIO product variant was used as a proxy for the default shipping fee.
    # The default shipping fee is now stored in application config
    # (:ledgr, :default_shipping_fee_cents). ENVIO is soft-deleted here so
    # historical data referencing it remains intact.
    execute """
    UPDATE product_variants
    SET deleted_at = NOW()
    WHERE sku = 'ENVIO' AND deleted_at IS NULL
    """
  end

  def down do
    execute """
    UPDATE product_variants
    SET deleted_at = NULL
    WHERE sku = 'ENVIO'
    """
  end
end
