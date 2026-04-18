defmodule Ledgr.Repos.HelloDoctor.Migrations.AddPhoneNormalizationTrigger do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION normalize_doctor_phone()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.phone := regexp_replace(NEW.phone, '[^0-9]', '', 'g');
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER doctors_normalize_phone
    BEFORE INSERT OR UPDATE OF phone ON doctors
    FOR EACH ROW
    EXECUTE FUNCTION normalize_doctor_phone();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS doctors_normalize_phone ON doctors;"
    execute "DROP FUNCTION IF EXISTS normalize_doctor_phone();"
  end
end
