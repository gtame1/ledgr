defmodule LedgrWeb.Domains.EscuelaDeDinero.StateLabels.Helpers do
  @moduledoc """
  Spanish labels and stamp-colour mappings for every Escuela de Dinero state
  vocabulary, plus the small formatters the templates need.

  Labels here are bound by the brand manual's banned vocabulary: never *curso,
  módulo, lección, clase, alumno, inscripción, temario, generación,
  certificado*, and never *educación financiera*, *asesoría en inversiones* or
  *recomendación personalizada*. Keep replacements inside the authorized set —
  *diagnóstico, movimiento, acompañamiento, guía, sistema, instalación, paso*.

  This module exists because HEEx forbids `alias`/`import` inside templates and
  several HTML modules need the same helpers. See the `use`-able wrapper below.
  """

  @tz "America/Mexico_City"

  # ── people.etapa (monotonic, terminal) ─────────────────────────────

  @etapa_order ~w(nuevo tc_pendiente diagnostico_en_curso diagnostico_listo acompanamiento)

  @etapa_labels %{
    "nuevo" => "Nuevo",
    "tc_pendiente" => "Consentimiento pendiente",
    "diagnostico_en_curso" => "Diagnóstico en curso",
    "diagnostico_listo" => "Diagnóstico entregado",
    "acompanamiento" => "Acompañamiento"
  }

  @doc "The five etapas in order. `etapa` only ever moves forward."
  def etapa_order, do: @etapa_order

  def etapa_label(nil), do: "—"
  def etapa_label(code), do: Map.get(@etapa_labels, code, code)

  # ── people.mode (cyclic) ───────────────────────────────────────────

  def mode_label(nil), do: "—"
  def mode_label("diagnostico"), do: "Diagnóstico"
  def mode_label("acompanamiento"), do: "Acompañamiento"
  def mode_label(code), do: code

  # ── diagnosticos.status ────────────────────────────────────────────

  def diagnostico_status_label(nil), do: "—"
  def diagnostico_status_label("in_progress"), do: "En curso"
  def diagnostico_status_label("complete"), do: "Entregado"
  def diagnostico_status_label("abandoned"), do: "Abandonado"
  def diagnostico_status_label(code), do: code

  def diagnostico_status_tone("complete"), do: "resuelto"
  def diagnostico_status_tone("in_progress"), do: "proceso"
  def diagnostico_status_tone("abandoned"), do: "riesgo"
  def diagnostico_status_tone(_), do: "neutral"

  # ── área estado (inside diagnosticos.areas JSONB) ──────────────────

  @doc "The four áreas the entrega scores, in the order they're installed."
  def area_order, do: ~w(colchon estructura_fiscal retiro seguros)

  def area_label(nil), do: "—"
  def area_label("colchon"), do: "Colchón"
  def area_label("estructura_fiscal"), do: "Estructura fiscal"
  def area_label("retiro"), do: "Retiro"
  def area_label("seguros"), do: "Seguros"
  def area_label("deuda"), do: "Deuda"
  def area_label(code), do: code

  # Only `colchon` ever uses en_proceso — the other three are binary.
  def area_estado_label(nil), do: "Sin dato"
  def area_estado_label("al_descubierto"), do: "Al descubierto"
  def area_estado_label("en_proceso"), do: "En proceso"
  def area_estado_label("instalado"), do: "Instalado"
  def area_estado_label(code), do: code

  def area_estado_tone("instalado"), do: "resuelto"
  def area_estado_tone("en_proceso"), do: "proceso"
  def area_estado_tone("al_descubierto"), do: "riesgo"
  def area_estado_tone(_), do: "neutral"

  @doc "Reads `areas -> <area> ->> 'estado'` out of the JSONB map, nil-safe."
  def area_estado(areas, area) when is_map(areas) do
    case Map.get(areas, area) do
      %{"estado" => estado} -> estado
      _ -> nil
    end
  end

  def area_estado(_areas, _area), do: nil

  # ── movimientos.estado ─────────────────────────────────────────────

  def movimiento_estado_label(nil), do: "—"
  def movimiento_estado_label("pendiente"), do: "Pendiente"
  def movimiento_estado_label("en_proceso"), do: "En proceso"
  def movimiento_estado_label("hecho"), do: "Hecho"
  def movimiento_estado_label("descartado"), do: "Descartado"
  def movimiento_estado_label(code), do: code

  def movimiento_estado_tone("hecho"), do: "resuelto"
  def movimiento_estado_tone("en_proceso"), do: "proceso"
  def movimiento_estado_tone("pendiente"), do: "riesgo"
  def movimiento_estado_tone(_), do: "neutral"

  # ── conversations ──────────────────────────────────────────────────

  def conversation_status_label(nil), do: "—"
  def conversation_status_label("active"), do: "Abierta"
  def conversation_status_label("closed"), do: "Cerrada"
  def conversation_status_label(code), do: code

  def initiated_by_label(nil), do: "—"
  def initiated_by_label("person"), do: "La persona"
  def initiated_by_label("business"), do: "Socio"
  def initiated_by_label(code), do: code

  def role_label("user"), do: "Persona"
  def role_label("assistant"), do: "Socio"
  def role_label("system"), do: "Sistema"
  def role_label(code), do: code

  # ── policing ───────────────────────────────────────────────────────

  def severity_label("CRITICAL"), do: "Crítico"
  def severity_label("WARNING"), do: "Advertencia"
  def severity_label("INFO"), do: "Aviso"
  def severity_label(code), do: code

  def severity_tone("CRITICAL"), do: "riesgo"
  def severity_tone("WARNING"), do: "proceso"
  def severity_tone("INFO"), do: "neutral"
  def severity_tone(_), do: "neutral"

  @doc """
  Human-readable name for a policing rule.

  The four CRITICAL rules are the compliance-relevant ones:
  `promesa_de_rendimiento` and `asesoria_en_inversiones` describe regulated
  activity in Mexico; `solicitud_de_credenciales` and `kubo_link_ungated` are
  hard brand rules.
  """
  def rule_label("solicitud_de_credenciales"), do: "Pidió credenciales"
  def rule_label("promesa_de_rendimiento"), do: "Prometió un rendimiento"
  def rule_label("asesoria_en_inversiones"), do: "Sonó a asesoría en inversiones"
  def rule_label("kubo_link_ungated"), do: "Liga de Kubo sin filtro"
  def rule_label("empty_assistant_reply"), do: "Respuesta vacía"
  def rule_label("mensaje_muy_largo"), do: "Mensaje muy largo"
  def rule_label("identity_hijack"), do: "Intento de suplantación"
  def rule_label("system_prompt_leak"), do: "Fuga del prompt"
  def rule_label("numero_inventado"), do: "Número inventado"
  def rule_label("outbound_send_failed"), do: "Falló el envío"
  def rule_label("double_asterisk"), do: "Doble asterisco"
  def rule_label("emoji_count_over"), do: "Demasiados emojis"
  def rule_label("traductor_violado"), do: "Palabra prohibida"
  def rule_label("deberias"), do: "Dijo «deberías»"
  def rule_label("porcentaje_sin_pesos"), do: "Porcentaje sin pesos"
  def rule_label("emoji_en_cifras"), do: "Emoji en las cifras"
  def rule_label(code), do: code

  # ── kubo ───────────────────────────────────────────────────────────

  def gate_reason_label("ok"), do: "Enviada"
  def gate_reason_label("disabled"), do: "Kubo apagado"
  def gate_reason_label("no_url"), do: "Sin liga configurada"
  def gate_reason_label("diagnostico_incompleto"), do: "Diagnóstico incompleto"
  def gate_reason_label("colchon_no_es_el_problema"), do: "El colchón no es el problema"
  def gate_reason_label("sin_nada_que_guardar"), do: "Sin nada que guardar"
  def gate_reason_label("ya_enviado"), do: "Ya se le envió"
  def gate_reason_label("opted_out"), do: "Se dio de baja"
  def gate_reason_label(code), do: code

  def outcome_label(nil), do: "Sin reportar"
  def outcome_label("abrio_cuenta"), do: "Abrió cuenta"
  def outcome_label("no"), do: "No abrió"
  def outcome_label("unknown"), do: "No se sabe"
  def outcome_label(code), do: code

  # ── respuestas slots ───────────────────────────────────────────────

  @doc "The six slots the diagnóstico must fill before the playback is sent."
  def required_slots do
    ~w(de_que_vives ingreso_promedio_mensual variabilidad gasto_fijo_mensual
       guardado_disponible que_tienes_montado)
  end

  def slot_label("de_que_vives"), do: "De qué vive"
  def slot_label("ingreso_promedio_mensual"), do: "Ingreso promedio al mes"
  def slot_label("variabilidad"), do: "Variabilidad"
  def slot_label("gasto_fijo_mensual"), do: "Gasto fijo al mes"
  def slot_label("guardado_disponible"), do: "Lo que tiene guardado"
  def slot_label("que_tienes_montado"), do: "Qué tiene montado"
  def slot_label("deuda_total"), do: "Deuda total"
  def slot_label("dependientes"), do: "Dependientes"
  def slot_label("meta"), do: "Meta"
  def slot_label(code), do: code

  def de_que_vives_label("freelance"), do: "Freelance"
  def de_que_vives_label("negocio"), do: "Negocio propio"
  def de_que_vives_label("comision"), do: "Comisión"
  def de_que_vives_label("mixto"), do: "Mixto"
  def de_que_vives_label("otro"), do: "Otro"
  def de_que_vives_label(code), do: code

  def confianza_label("alta"), do: "alta"
  def confianza_label("media"), do: "media"
  def confianza_label("baja"), do: "baja"
  def confianza_label(code), do: code

  def montado_label("afore"), do: "Afore"
  def montado_label("seguros"), do: "Seguros"
  def montado_label("factura"), do: "Factura"
  def montado_label("deuda"), do: "Deuda"
  def montado_label(code), do: code

  # ── formatters ─────────────────────────────────────────────────────

  @doc """
  Pesos, always monospaced at the call site (`class="ed-cifra"`).

  Brand rule: every money figure is monospaced. No exceptions, no cents —
  this ICP thinks in whole pesos.
  """
  def mxn(nil), do: "—"

  def mxn(amount) when is_number(amount) do
    "$" <> thousands(round(amount))
  end

  def mxn(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_integer() |> then(&mxn/1)

  @doc "Integer with thin thousands separators."
  def thousands(n) when is_integer(n) do
    sign = if n < 0, do: "-", else: ""

    digits =
      n
      |> abs()
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")
      |> String.reverse()

    sign <> digits
  end

  def thousands(other), do: to_string(other)

  @doc "A percentage rendered from an already-computed float. Nil-safe."
  def pct(nil), do: "—"
  def pct(v) when is_number(v), do: "#{v}%"
  def pct(v), do: to_string(v)

  @doc """
  Days without invoicing — the headline number.

  Rendered as a bare integer plus its unit so it reads like a measurement,
  not a score.
  """
  def dias(nil), do: "—"
  def dias(0), do: "0 días"
  def dias(1), do: "1 día"
  def dias(n) when is_integer(n), do: "#{thousands(n)} días"
  def dias(n), do: to_string(n)

  @doc """
  Which colchón band a day-count falls in. Bands are the bot's own thresholds
  (>= 90 instalado, >= 30 en_proceso), plus a "this week" band below 7.
  """
  def dias_band(nil), do: nil
  def dias_band(n) when n < 7, do: :critico
  def dias_band(n) when n < 30, do: :corto
  def dias_band(n) when n < 90, do: :medio
  def dias_band(_n), do: :largo

  def dias_band_label(:critico), do: "Menos de 7 días"
  def dias_band_label(:corto), do: "7 a 29 días"
  def dias_band_label(:medio), do: "30 a 89 días"
  def dias_band_label(:largo), do: "90 días o más"
  def dias_band_label(_), do: "Sin dato"

  def dias_tone(nil), do: "neutral"

  def dias_tone(n) when is_integer(n) do
    case dias_band(n) do
      :largo -> "resuelto"
      :medio -> "proceso"
      _ -> "riesgo"
    end
  end

  def dias_tone(_), do: "neutral"

  @doc """
  Phone as the bot itself shows it in alerts: last four digits only.

  Every index in this app lists real people's numbers alongside their income.
  Masking by default costs nothing and means a shared screen isn't a leak; the
  full number is still on the persona detail page when an operator needs it.
  """
  def phone_masked(nil), do: "—"

  def phone_masked(phone) when is_binary(phone) do
    digits = String.replace(phone, ~r/\D/, "")

    case String.length(digits) do
      n when n >= 4 -> "··· " <> String.slice(digits, -4, 4)
      _ -> phone
    end
  end

  def phone_masked(other), do: to_string(other)

  @doc """
  Full phone, grouped. Only used on detail pages.

  Mexican WhatsApp numbers arrive in two shapes: `52` + 10 digits, and the
  legacy `52` + `1` + 10 digits that Meta still hands back for many accounts.
  Both are the same subscriber, so both render identically.
  """
  def phone_full(nil), do: "—"

  def phone_full(phone) when is_binary(phone) do
    case String.replace(phone, ~r/\D/, "") do
      <<"521", rest::binary-size(10)>> -> format_mx(rest)
      <<"52", rest::binary-size(10)>> -> format_mx(rest)
      _ -> phone
    end
  end

  def phone_full(other), do: to_string(other)

  defp format_mx(<<a::binary-size(2), b::binary-size(4), c::binary-size(4)>>),
    do: "+52 #{a} #{b} #{c}"

  @doc """
  A UTC timestamp shown in Mexico City time.

  Everything the bot writes is TIMESTAMPTZ, so this is a real conversion —
  don't swap it for the shared `fmt_datetime/1`, which renders UTC.
  """
  def mx_datetime(nil), do: "—"

  def mx_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!(@tz)
    |> Calendar.strftime("%d/%m/%Y %H:%M")
  end

  def mx_datetime(_), do: "—"

  def mx_date(nil), do: "—"

  def mx_date(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!(@tz)
    |> Calendar.strftime("%d/%m/%Y")
  end

  def mx_date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
  def mx_date(_), do: "—"

  @doc "Relative age in plain Spanish: \"hace 3 días\". Nil-safe."
  def hace(nil), do: "—"

  def hace(%DateTime{} = dt) do
    case DateTime.diff(DateTime.utc_now(), dt, :second) do
      s when s < 60 -> "hace un momento"
      s when s < 3_600 -> "hace #{div(s, 60)} min"
      s when s < 86_400 -> "hace #{div(s, 3_600)} h"
      s when s < 2_592_000 -> "hace #{div(s, 86_400)} d"
      s -> "hace #{div(s, 2_592_000)} meses"
    end
  end

  def hace(_), do: "—"

  @doc "True when a pendiente movimiento is past its due date."
  def vencido?(%{estado: "pendiente", due_at: %DateTime{} = due}) do
    DateTime.compare(due, DateTime.utc_now()) == :lt
  end

  def vencido?(_), do: false

  @doc "Percentage width for a bar, guarding zero denominators."
  def bar_pct(_value, 0), do: 0
  def bar_pct(_value, nil), do: 0
  def bar_pct(nil, _total), do: 0
  def bar_pct(value, total), do: Float.round(value / total * 100, 1)
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.StateLabels do
  @moduledoc """
  `use` this in any Escuela de Dinero HTML module so the label helpers are
  callable by short name inside its embedded HEEx templates:

      defmodule LedgrWeb.Domains.EscuelaDeDinero.FooHTML do
        use LedgrWeb, :html
        use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
        embed_templates "foo_html/*"
      end
  """

  defmacro __using__(_opts) do
    quote do
      import LedgrWeb.Domains.EscuelaDeDinero.StateLabels.Helpers
    end
  end
end
