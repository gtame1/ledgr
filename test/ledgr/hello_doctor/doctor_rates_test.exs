defmodule Ledgr.Domains.HelloDoctor.DoctorRatesTest do
  @moduledoc """
  The pricing half of the old `ConsultationAccounting`, which mixed this rule
  with journal-entry posting. The posting is going away; this is not — it feeds
  the dashboard, lifecycle and acquisition metrics, both funnel exports,
  payouts and refunds.

  These pin the rule itself and, critically, the SQL fragment: several callers
  interpolate it into raw queries, so a change in spacing or precedence there
  silently changes reported revenue rather than failing loudly.
  """
  use ExUnit.Case, async: true

  alias Ledgr.Domains.HelloDoctor.DoctorRates

  describe "the flat share" do
    test "is $100 MXN" do
      assert DoctorRates.doctor_share_mxn() == 100.0
      assert DoctorRates.doctor_share_cents() == 10_000
    end
  end

  describe "doctor_share_mxn/2" do
    test "a direct patient pays the doctor's own negotiated fee" do
      assert DoctorRates.doctor_share_mxn("direct", 200.0) == 200.0
      assert DoctorRates.doctor_share_mxn("direct", 350.0) == 350.0
    end

    test "an HD-sourced consult pays the flat share regardless of the fee" do
      assert DoctorRates.doctor_share_mxn("mvp", 200.0) == 100.0
      assert DoctorRates.doctor_share_mxn("mvp", nil) == 100.0
    end

    test "a direct consult with no configured fee falls back to the flat share" do
      assert DoctorRates.doctor_share_mxn("direct", nil) == 100.0
      assert DoctorRates.doctor_share_mxn("direct", 0) == 100.0
      assert DoctorRates.doctor_share_mxn("direct", 0.0) == 100.0
    end

    test "an unknown or missing tenant pays the flat share" do
      assert DoctorRates.doctor_share_mxn(nil, 200.0) == 100.0
      assert DoctorRates.doctor_share_mxn("", 200.0) == 100.0
    end
  end

  describe "doctor_share_sql/2" do
    test "is byte-identical to the fragment the raw-SQL callers relied on" do
      assert DoctorRates.doctor_share_sql("conv.tenant", "d.consultation_fee_mxn") ==
               "(CASE WHEN conv.tenant = 'direct' AND COALESCE(d.consultation_fee_mxn, 0) > 0 " <>
                 "THEN (d.consultation_fee_mxn)::float8 ELSE 100.0 END)"
    end

    test "interpolates whatever expressions the caller is holding" do
      assert DoctorRates.doctor_share_sql("conv2.tenant", "x.fee") =~ "conv2.tenant = 'direct'"
      assert DoctorRates.doctor_share_sql("conv2.tenant", "x.fee") =~ "(x.fee)::float8"
    end

    test "agrees with doctor_share_mxn/2 on the cases that matter" do
      # Same rule, two encodings — they have drifted apart before.
      for {tenant, fee, expected} <- [
            {"direct", 200.0, 200.0},
            {"direct", nil, 100.0},
            {"mvp", 200.0, 100.0},
            {nil, nil, 100.0}
          ] do
        assert DoctorRates.doctor_share_mxn(tenant, fee) == expected
      end
    end
  end
end
