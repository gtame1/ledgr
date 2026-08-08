defmodule Ledgr.Domains.EscuelaDeDinero.DashboardMetricsTest do
  use Ledgr.DataCase

  alias Ledgr.Domains.EscuelaDeDinero.DashboardMetrics
  alias Ledgr.Repos.EscuelaDeDinero, as: Repo

  setup do
    Ledgr.Repo.put_active_repo(Repo)
    :ok
  end

  # The bot owns these tables, so tests insert with raw SQL rather than through
  # changesets we deliberately don't have.
  defp person!(id, etapa, opts \\ []) do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO people (id, phone, display_name, etapa, mode, terms_accepted,
                          latest_diagnostico_id, created_at, updated_at)
      VALUES ($1, $2, $3, $4, 'diagnostico', true, $5, now(), now())
      """,
      [id, "52155#{id}", "P#{id}", etapa, opts[:latest_diagnostico_id]]
    )
  end

  # `areas` is passed as a map, not a JSON string. With a `$n::jsonb` cast
  # Postgrex types the parameter as jsonb and JSON-encodes whatever it is given,
  # so a binary lands in the column as a quoted JSON *string* and every
  # `-> 'key'` lookup against it returns NULL — silently, with no error.
  defp diagnostico!(id, person_id, opts) do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO diagnosticos (id, person_id, version, status, schema_version,
                                started_at, dias_sin_facturar, headline, respuestas,
                                areas, movimientos)
      VALUES ($1, $2, 1, $3, 'v1', now(), $4, '{}'::jsonb, '{}'::jsonb, $5, '[]'::jsonb)
      """,
      [id, person_id, opts[:status], opts[:dias], opts[:areas] || %{}]
    )
  end

  describe "etapa_funnel/0" do
    test "walks the known etapas cumulatively" do
      person!("a", "nuevo")
      person!("b", "diagnostico_listo")
      person!("c", "acompanamiento")

      %{total: total, rows: rows} = DashboardMetrics.etapa_funnel()

      assert total == 3

      reached = Map.new(rows, &{&1.etapa, &1.reached})
      # Everyone reached `nuevo`; only b and c got past the consent gate.
      assert reached["nuevo"] == 3
      assert reached["tc_pendiente"] == 2
      assert reached["diagnostico_en_curso"] == 2
      assert reached["diagnostico_listo"] == 2
      assert reached["acompanamiento"] == 1
    end

    test "an etapa the bot adds does not inflate the funnel" do
      # Regression: `total` used to sum EVERY etapa while the walk only consumed
      # the known ones, so an unmapped value silently added itself to every bar
      # and never came back off. The bot owns ETAPA_ORDER and can grow it.
      person!("a", "nuevo")
      person!("b", "acompanamiento")
      person!("c", "etapa_que_no_conocemos")

      %{total: total, rows: rows, desconocidas: desconocidas} =
        DashboardMetrics.etapa_funnel()

      assert total == 2, "unknown etapas must not count toward the funnel total"

      reached = Map.new(rows, &{&1.etapa, &1.reached})
      assert reached["nuevo"] == 2
      assert reached["acompanamiento"] == 1

      # ...and it must be visible rather than silently dropped.
      assert desconocidas == [{"etapa_que_no_conocemos", 1}]
    end
  end

  describe "empty database" do
    test "every section returns zeros instead of raising" do
      today = Ledgr.Domains.EscuelaDeDinero.today()
      m = DashboardMetrics.all(Date.add(today, -29), today)

      assert m.kpis.tasa_completado == 0.0
      assert m.diagnostico_funnel.iniciados == 0
      assert m.etapa_funnel.total == 0
      assert m.dias_distribution.total == 0
      assert m.dias_distribution.mediana == nil
      assert m.movimientos.tasa_instalacion == 0.0
      assert m.atorados == []
      assert Enum.all?(m.areas, &(&1.total == 0))
      assert length(m.daily_series) == 30
    end
  end

  describe "dias_distribution/0" do
    test "bands on the colchón thresholds and reports the median, not the mean" do
      for {pid, did, dias} <- [{"a", "d1", 0}, {"b", "d2", 40}, {"c", "d3", 3650}] do
        diagnostico!(did, pid, status: "complete", dias: dias)
        person!(pid, "acompanamiento", latest_diagnostico_id: did)
      end

      d = DashboardMetrics.dias_distribution()
      bands = Map.new(d.bands, &{&1.band, &1.count})

      assert d.total == 3
      assert bands[:critico] == 1
      assert bands[:medio] == 1
      assert bands[:largo] == 1
      # Mean would be 1230 — one outlier. The median is the honest number.
      assert d.mediana == 40
    end
  end

  describe "areas_breakdown/0" do
    test "a missing área key surfaces as sin_dato rather than vanishing" do
      # The bot omits a boolean área when the person never answered for it
      # (entrega.evaluar_areas). That gap is information, not noise.
      diagnostico!("d1", "a",
        status: "complete",
        dias: 10,
        areas: %{"colchon" => %{"estado" => "al_descubierto", "dias" => 10}}
      )

      person!("a", "acompanamiento", latest_diagnostico_id: "d1")

      by_area = Map.new(DashboardMetrics.areas_breakdown(), &{&1.area, &1})

      colchon = Map.new(by_area["colchon"].segments, &{&1.estado, &1.count})
      assert colchon["al_descubierto"] == 1

      retiro = Map.new(by_area["retiro"].segments, &{&1.estado, &1.count})
      assert retiro["sin_dato"] == 1
    end
  end
end
