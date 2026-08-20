defmodule Ledgr.Domains.Viaxe.TravelDocuments do
  @moduledoc """
  Context for managing travel documents: passports, visas, and loyalty programs.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.Viaxe.TravelDocuments.{Passport, Visa, LoyaltyProgram}

  # ── Listing (all customers) ─────────────────────────────────────────

  def list_passports do
    Passport
    |> order_by([p], asc_nulls_last: p.expiry_date)
    |> preload(:customer)
    |> Repo.all()
  end

  def list_visas do
    Visa
    |> order_by([v], asc_nulls_last: v.expiry_date)
    |> preload(:customer)
    |> Repo.all()
  end

  def list_loyalty_programs do
    LoyaltyProgram
    |> order_by([l], asc: l.program_name)
    |> preload(:customer)
    |> Repo.all()
  end

  # ── Passports ──────────────────────────────────────────────────────

  def create_passport(attrs \\ %{}) do
    %Passport{}
    |> Passport.changeset(attrs)
    |> Repo.insert()
  end

  def delete_passport(id) do
    case Repo.get(Passport, id) do
      nil -> {:error, :not_found}
      passport -> Repo.delete(passport)
    end
  end

  def change_passport(%Passport{} = passport, attrs \\ %{}) do
    Passport.changeset(passport, attrs)
  end

  # ── Visas ──────────────────────────────────────────────────────────

  def create_visa(attrs \\ %{}) do
    %Visa{}
    |> Visa.changeset(attrs)
    |> Repo.insert()
  end

  def delete_visa(id) do
    case Repo.get(Visa, id) do
      nil -> {:error, :not_found}
      visa -> Repo.delete(visa)
    end
  end

  def change_visa(%Visa{} = visa, attrs \\ %{}) do
    Visa.changeset(visa, attrs)
  end

  # ── Loyalty Programs ───────────────────────────────────────────────

  def create_loyalty_program(attrs \\ %{}) do
    %LoyaltyProgram{}
    |> LoyaltyProgram.changeset(attrs)
    |> Repo.insert()
  end

  def delete_loyalty_program(id) do
    case Repo.get(LoyaltyProgram, id) do
      nil -> {:error, :not_found}
      program -> Repo.delete(program)
    end
  end

  def change_loyalty_program(%LoyaltyProgram{} = program, attrs \\ %{}) do
    LoyaltyProgram.changeset(program, attrs)
  end
end
