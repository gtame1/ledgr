defmodule Ledgr.Domains.HelloDoctor.MedikitSpecialties do
  @moduledoc """
  Medikit specialty catalog — the `SpecialtyId` values Medikit's /doctors
  endpoint requires, provided by the Medikit Account Manager.

  The full PRD catalog (Salesforce ids) ships embedded in `@default_catalog`
  below, sourced from "Catálogo de especialidades ORG Medikit PRD". It can be
  overridden without a code change by setting:

      config :ledgr, :medikit,
        specialty_catalog: [
          %{id: "0bc8c000000XcnDAAS", name: "Medicina General"},
          ...
        ]

  A non-empty `:specialty_catalog` in config fully replaces the embedded list
  (e.g. to point at a different Medikit org). When it is absent/empty the
  embedded catalog is used.
  """

  # PRD catalog — %{name, id}. 216 entries. Keep in sync with the source xlsx
  # if Medikit revises it; overridable via config for a different org.
  @default_catalog [
    %{name: "Alergología", id: "0bc8c000000XclFAAS"},
    %{name: "Alergología Pediátrica", id: "0bc8c000000XclGAAS"},
    %{name: "Algología", id: "0bc8c000000XclHAAS"},
    %{name: "Análisis Clínicos", id: "0bc8c000000XclIAAS"},
    %{name: "Anatomía Patológica", id: "0bc8c000000XclJAAS"},
    %{name: "Anatomía Patológica Pediátrica", id: "0bc8c000000XclKAAS"},
    %{name: "Anatomopatología", id: "0bc8c000000XclLAAS"},
    %{name: "Andrología", id: "0bc8c000000XclMAAS"},
    %{name: "Anestesiología", id: "0bc8c000000XclNAAS"},
    %{name: "Anestesiología Pediátrica", id: "0bc8c000000XclOAAS"},
    %{name: "Angiología,Cirugía Vascular Y Endovascular", id: "0bc8c000000XclPAAS"},
    %{name: "Asma", id: "0bc8c000000XclQAAS"},
    %{name: "Atención Primaria En Salud", id: "0bc8c000000XclRAAS"},
    %{name: "Audiología", id: "0bc8c000000XegJAAS"},
    %{name: "Ayudante", id: "0bc8c000000XclSAAS"},
    %{name: "Bacteriología", id: "0bc8c000000XclTAAS"},
    %{name: "Biología De La Reproducción Humana", id: "0bc8c000000XclUAAS"},
    %{name: "Broncoscopía Intervencionista", id: "0bc8c000000XclVAAS"},
    %{name: "Broncoscopía Intervencionista Pediátrica", id: "0bc8c000000XclWAAS"},
    %{name: "Calidad De La Atención Cliníca", id: "0bc8c000000XclXAAS"},
    %{name: "Cardiología Clínica", id: "0bc8c000000XclYAAS"},
    %{name: "Cardiología Intervencionista", id: "0bc8c000000XclZAAS"},
    %{name: "Cardiología Intervencionista En Cardiopatías Congénitas", id: "0bc8c000000XclaAAC"},
    %{name: "Cardiología Pediátrica", id: "0bc8c000000XclbAAC"},
    %{name: "Cirugía Bariátrica", id: "0bc8c000000XclcAAC"},
    %{name: "Cirugía Bucal", id: "0bc8c000000XcldAAC"},
    %{name: "Cirugía Cardiaca En Adultos", id: "0bc8c000000XcleAAC"},
    %{name: "Cirugía Cardiaca En Pediatría", id: "0bc8c000000XclfAAC"},
    %{name: "Cirugía Cardiotorácica", id: "0bc8c000000XclgAAC"},
    %{name: "Cirugía Cardiovascular", id: "0bc8c000000XclhAAC"},
    %{name: "Cirugía De Cabeza Y Cuello", id: "0bc8c000000XcliAAC"},
    %{name: "Cirugía De Columna", id: "0bc8c000000XcljAAC"},
    %{name: "Cirugía De Torax", id: "0bc8c000000XclkAAC"},
    %{name: "Cirugía De Tórax Pediátricano Cardiaca", id: "0bc8c000000XcllAAC"},
    %{name: "Cirugía De Trasplantes", id: "0bc8c000000XclmAAC"},
    %{name: "Cirugía Del Aparato Digestivo", id: "0bc8c000000XclnAAC"},
    %{name: "Cirugía Endocrinologica", id: "0bc8c000000XcloAAC"},
    %{name: "Cirugía Gastroenterologica", id: "0bc8c000000XclpAAC"},
    %{name: "Cirugía General", id: "0bc8c000000XclqAAC"},
    %{name: "Cirugía General Pediatrica", id: "0bc8c000000XclrAAC"},
    %{name: "Cirugía Maxilofacial", id: "0bc8c000000XclsAAC"},
    %{name: "Cirugía Neumológica", id: "0bc8c000000XegOAAS"},
    %{name: "Cirugía Neurológica", id: "0bc8c000000XcltAAC"},
    %{name: "Cirugía Neurológica Pediátrica", id: "0bc8c000000XcluAAC"},
    %{name: "Cirugía Oncológica", id: "0bc8c000000XclvAAC"},
    %{name: "Cirugía Oncológica Pediátrica", id: "0bc8c000000XclwAAC"},
    %{name: "Cirugía Oral Y Maxilofacial", id: "0bc8c000000XclxAAC"},
    %{name: "Cirugía Para Los Servicios Rurales De Salud", id: "0bc8c000000XclyAAC"},
    %{name: "Cirugía Pediátrica", id: "0bc8c000000XclzAAC"},
    %{name: "Cirugía Plástica, Estética Y Reconstructiva", id: "0bc8c000000Xcm0AAC"},
    %{name: "Cirugía Torácicano Cardiaca", id: "0bc8c000000Xcm1AAC"},
    %{name: "Cirugía Vascular Periferica", id: "0bc8c000000Xcm2AAC"},
    %{name: "Cirujano", id: "0bc8c000000Xcm3AAC"},
    %{name: "Cirujano Y Homeópata", id: "0bc8c000000Xcm4AAC"},
    %{name: "Cirujano Y Partero", id: "0bc8c000000Xcm5AAC"},
    %{name: "Citogénica", id: "0bc8c000000Xcm6AAC"},
    %{name: "Coloproctología", id: "0bc8c000000Xcm7AAC"},
    %{name: "Comunicación Audiología, Otoneurología Y Foniatría", id: "0bc8c000000Xcm8AAC"},
    %{name: "Cuidados Paliativos", id: "0bc8c000000Xcm9AAC"},
    %{name: "Dermatología", id: "0bc8c000000XcmAAAS"},
    %{name: "Dermatología Pediátrica", id: "0bc8c000000XcmBAAS"},
    %{name: "Diabetología", id: "0bc8c000000XcmCAAS"},
    %{name: "Ecocardiografía De Adultos", id: "0bc8c000000XcmDAAS"},
    %{name: "Ecocardiografía Pediátrica", id: "0bc8c000000XcmEAAS"},
    %{name: "Ecografía", id: "0bc8c000000XcmFAAS"},
    %{name: "Electrofisiología", id: "0bc8c000000XcmGAAS"},
    %{name: "Emergenciología", id: "0bc8c000000XcmHAAS"},
    %{name: "Endocrinología", id: "0bc8c000000XcmIAAS"},
    %{name: "Endocrinología Pediátrica", id: "0bc8c000000XcmJAAS"},
    %{name: "Endodoncia", id: "0bc8c000000XcmKAAS"},
    %{name: "Endoscopía Del Aparato Digestivo", id: "0bc8c000000XcmLAAS"},
    %{name: "Endoscopía Torácica", id: "0bc8c000000XcmMAAS"},
    %{name: "Enfermería", id: "0bc8c000000XcmNAAS"},
    %{name: "Epidemiología", id: "0bc8c000000XcmOAAS"},
    %{name: "Estomatología", id: "0bc8c000000XcmPAAS"},
    %{name: "Farmacología", id: "0bc8c000000XcmQAAS"},
    %{name: "Fisiología Respiratoria", id: "0bc8c000000XcmRAAS"},
    %{name: "Fisiología Respiratoria Pediátrica", id: "0bc8c000000XcmSAAS"},
    %{name: "Fisioterapia", id: "0bc8c000000XcmTAAS"},
    %{name: "Foniatria", id: "0bc8c000000XcmUAAS"},
    %{name: "Gastroenterología", id: "0bc8c000000XcmVAAS"},
    %{name: "Gastroenterologia / Endoscopía", id: "0bc8c000000XcmWAAS"},
    %{name: "Gastroenterología Pediátrica", id: "0bc8c000000XcmXAAS"},
    %{name: "Gastroenterología Y Nutrición Pediátrica", id: "0bc8c000000XcmYAAS"},
    %{name: "Genética Médica", id: "0bc8c000000XcmZAAS"},
    %{name: "Genética Molecular", id: "0bc8c000000XcmaAAC"},
    %{name: "Geriatría", id: "0bc8c000000XcmbAAC"},
    %{name: "Gerontología", id: "0bc8c000000XcmcAAC"},
    %{name: "Ginecología Colposcopista", id: "0bc8c000000XcmdAAC"},
    %{name: "Ginecología Oncológica", id: "0bc8c000000XcmeAAC"},
    %{name: "Ginecología Y Obstetricia", id: "0bc8c000000XcmfAAC"},
    %{name: "Hematología", id: "0bc8c000000XcmgAAC"},
    %{name: "Hematología Pediátrica", id: "0bc8c000000XcmhAAC"},
    %{name: "Hepatología", id: "0bc8c000000XcmiAAC"},
    %{name: "Hipnoterapeuta", id: "0bc8c000000XcmjAAC"},
    %{name: "Homeopatía", id: "0bc8c000000XcmkAAC"},
    %{name: "Imagen De La Mama", id: "0bc8c000000XcmlAAC"},
    %{name: "Imagen Del Sistema Musculoesquelético", id: "0bc8c000000XcmmAAC"},
    %{name: "Imagenología Diagnóstica Y Terapéutica", id: "0bc8c000000XcmnAAC"},
    %{name: "Implantología Oral", id: "0bc8c000000XcmoAAC"},
    %{name: "Infectología Adultos", id: "0bc8c000000XcmpAAC"},
    %{name: "Infectología Pediátrica", id: "0bc8c000000XcmqAAC"},
    %{name: "Infertilidad", id: "0bc8c000000XcmrAAC"},
    %{name: "Ingeniería Biomédica General", id: "0bc8c000000XcmsAAC"},
    %{name: "Inmunología Clínica Y Alergia", id: "0bc8c000000XcmtAAC"},
    %{name: "Intensivista", id: "0bc8c000000XcmuAAC"},
    %{name: "Licenciado En Medicina", id: "0bc8c000000XcmvAAC"},
    %{name: "Mastología", id: "0bc8c000000XcmwAAC"},
    %{name: "Medicina Aeroespacial", id: "0bc8c000000XcmxAAC"},
    %{name: "Medicina Alternativa", id: "0bc8c000000XcmyAAC"},
    %{name: "Medicina Clínica", id: "0bc8c000000XcmzAAC"},
    %{name: "Medicina Crítica", id: "0bc8c000000Xcn0AAC"},
    %{name: "Medicina Crítica En Obstetricia", id: "0bc8c000000Xcn1AAC"},
    %{name: "Medicina De Rehabilitación", id: "0bc8c000000Xcn2AAC"},
    %{name: "Medicina De Urgencias", id: "0bc8c000000Xcn3AAC"},
    %{name: "Medicina Del Deporte", id: "0bc8c000000Xcn4AAC"},
    %{name: "Medicina Del Enfermo Pediátrico En Estado Crítico", id: "0bc8c000000Xcn5AAC"},
    %{
      name: "Medicina Del Niño Y Del Adulto Para Los Servicios Rurales De Salud",
      id: "0bc8c000000Xcn6AAC"
    },
    %{name: "Medicina Del Sueño", id: "0bc8c000000Xcn7AAC"},
    %{name: "Medicina Del Trabajo", id: "0bc8c000000Xcn8AAC"},
    %{name: "Medicina Del Trabajo Y Ambiental", id: "0bc8c000000Xcn9AAC"},
    %{name: "Medicina Estética", id: "0bc8c000000XcnAAAS"},
    %{name: "Medicina Familiar", id: "0bc8c000000XcnBAAS"},
    %{name: "Medicina Fisica Rehabilitacion", id: "0bc8c000000XcnCAAS"},
    %{name: "Medicina General", id: "0bc8c000000XcnDAAS"},
    %{name: "Medicina Integrada", id: "0bc8c000000XcnEAAS"},
    %{name: "Medicina Intensiva", id: "0bc8c000000XcnFAAS"},
    %{name: "Medicina Interna", id: "0bc8c000000XcnGAAS"},
    %{name: "Medicina Legal Y Forense", id: "0bc8c000000XcnHAAS"},
    %{name: "Medicina Materno-Fetal", id: "0bc8c000000XcnIAAS"},
    %{name: "Medicina Nuclear", id: "0bc8c000000XcnJAAS"},
    %{name: "Medicina Ocupacional", id: "0bc8c000000XcnKAAS"},
    %{name: "Medicina Preventiva", id: "0bc8c000000XcnLAAS"},
    %{name: "Medicina Tropical", id: "0bc8c000000XcnMAAS"},
    %{name: "Medicinanuclearcardiológica", id: "0bc8c000000XcnNAAS"},
    %{name: "Medicinanuclearoncológica, Molecular Y Terapéutica", id: "0bc8c000000XcnOAAS"},
    %{name: "Médico Cirujano", id: "0bc8c000000XcnPAAS"},
    %{name: "Médico Cirujano Homeópata", id: "0bc8c000000XcnQAAS"},
    %{name: "Médico Cirujano Y Partero", id: "0bc8c000000XcnRAAS"},
    %{name: "Médico Homeópata", id: "0bc8c000000XcnSAAS"},
    %{name: "Nefrología", id: "0bc8c000000XcnTAAS"},
    %{name: "Nefrología Pediátrica", id: "0bc8c000000XcnUAAS"},
    %{name: "Neonatología", id: "0bc8c000000XcnVAAS"},
    %{name: "Neumología", id: "0bc8c000000XcnWAAS"},
    %{name: "Neumología Pediátrica", id: "0bc8c000000XcnXAAS"},
    %{name: "Neuroanestesiología", id: "0bc8c000000XcnYAAS"},
    %{name: "Neurocirugía", id: "0bc8c000000XcnZAAS"},
    %{name: "Neurocirugía Pediatrica", id: "0bc8c000000XcnaAAC"},
    %{name: "Neurofisiología Clínica", id: "0bc8c000000XcnbAAC"},
    %{name: "Neurología", id: "0bc8c000000XcncAAC"},
    %{name: "Neurología Adultos", id: "0bc8c000000XcndAAC"},
    %{name: "Neurología Pediátrica", id: "0bc8c000000XcneAAC"},
    %{name: "Neurootología", id: "0bc8c000000XcnfAAC"},
    %{name: "Neuropatología", id: "0bc8c000000XcngAAC"},
    %{name: "Neuropsicología", id: "0bc8c000000XcnhAAC"},
    %{name: "Neuroradiología", id: "0bc8c000000XcniAAC"},
    %{name: "Nutrición", id: "0bc8c000000XcnjAAC"},
    %{name: "Nutricion Clinica", id: "0bc8c000000XcnkAAC"},
    %{name: "Nutriologia", id: "0bc8c000000XcnlAAC"},
    %{name: "Nutriología Pediátrica", id: "0bc8c000000XcnmAAC"},
    %{name: "Odontologia", id: "0bc8c000000XcnnAAC"},
    %{name: "Odontopediatria", id: "0bc8c000000XcnoAAC"},
    %{name: "Oftalmología", id: "0bc8c000000XcnpAAC"},
    %{name: "Oftalmología Pediátrica", id: "0bc8c000000XcnqAAC"},
    %{name: "Oncología Médica", id: "0bc8c000000XcnrAAC"},
    %{name: "Oncología Pediátrica", id: "0bc8c000000XcnsAAC"},
    %{name: "Ortopedia Y Traumatología", id: "0bc8c000000XcntAAC"},
    %{name: "Ortopedia Y Traumatologia Pediatrica", id: "0bc8c000000XcnuAAC"},
    %{name: "Otoneurologia", id: "0bc8c000000XcnvAAC"},
    %{name: "Otorrinolaringología", id: "0bc8c000000XcnwAAC"},
    %{name: "Otorrinolaringología Pediátrica", id: "0bc8c000000XcnxAAC"},
    %{name: "Otorrinolaringología Y Cirugía De Cabeza Y Cuello", id: "0bc8c000000XcnyAAC"},
    %{name: "Otra", id: "0bc8c000000XcnzAAC"},
    %{name: "Parasitología", id: "0bc8c000000Xco0AAC"},
    %{name: "Parodoncia", id: "0bc8c000000Xco1AAC"},
    %{name: "Patología Clínica", id: "0bc8c000000Xco2AAC"},
    %{name: "Pediatría", id: "0bc8c000000Xco3AAC"},
    %{name: "Pediatría Dermatología", id: "0bc8c000000Xco4AAC"},
    %{name: "Pediatría Emergenciología", id: "0bc8c000000Xco5AAC"},
    %{name: "Pediatría Homeopática", id: "0bc8c000000Xco6AAC"},
    %{name: "Pediatría Integral", id: "0bc8c000000Xco7AAC"},
    %{name: "Pediatría Nefrología", id: "0bc8c000000Xco8AAC"},
    %{name: "Pediatría Neonatólogos", id: "0bc8c000000Xco9AAC"},
    %{name: "Pediatría Neumología", id: "0bc8c000000XcoAAAS"},
    %{name: "Pediatría Oncológica", id: "0bc8c000000XcoBAAS"},
    %{name: "Perinatologia", id: "0bc8c000000XcoCAAS"},
    %{name: "Podiatria", id: "0bc8c000000XcoDAAS"},
    %{name: "Proctología", id: "0bc8c000000XcoEAAS"},
    %{name: "Psicología", id: "0bc8c000000XcoFAAS"},
    %{name: "Psiquiatría", id: "0bc8c000000XcoGAAS"},
    %{name: "Psiquiatría Infantil Y De La Adolescencia", id: "0bc8c000000XcoHAAS"},
    %{name: "Radio Oncología", id: "0bc8c000000XcoIAAS"},
    %{name: "Radiología E Imagen", id: "0bc8c000000XcoJAAS"},
    %{name: "Radiologia Intervencionista", id: "0bc8c000000XcoKAAS"},
    %{name: "Radiología Pediátrica", id: "0bc8c000000XcoLAAS"},
    %{name: "Radiología Vascular E Intervencionista", id: "0bc8c000000XcoMAAS"},
    %{name: "Radioterapia", id: "0bc8c000000XcoNAAS"},
    %{name: "Rehabilitación", id: "0bc8c000000XcoOAAS"},
    %{name: "Rehabilitación Cardiaca Y Prevención Secundaria", id: "0bc8c000000XcoPAAS"},
    %{name: "Rehabilitación Pulmonar", id: "0bc8c000000XcoQAAS"},
    %{name: "Rehabilitación Pulmonar Pediátrica", id: "0bc8c000000XcoRAAS"},
    %{name: "Reumatología", id: "0bc8c000000XcoSAAS"},
    %{name: "Reumatología Pediátrica", id: "0bc8c000000XcoTAAS"},
    %{name: "Salud Pública", id: "0bc8c000000XcoUAAS"},
    %{name: "Salud Sexual Y Reproductiva", id: "0bc8c000000XcoVAAS"},
    %{name: "Terapia Endovascular Neurológica", id: "0bc8c000000XcoWAAS"},
    %{name: "Terapia Intensiva", id: "0bc8c000000XcoXAAS"},
    %{name: "Terapista En Comunicación Humana", id: "0bc8c000000XcoYAAS"},
    %{name: "Trasplante Renal", id: "0bc8c000000XcoZAAS"},
    %{name: "Traumatología", id: "0bc8c000000XcoaAAC"},
    %{name: "Ultrasonografía", id: "0bc8c000000XcobAAC"},
    %{name: "Urgencias Pediátricas", id: "0bc8c000000XcocAAC"},
    %{name: "Urología", id: "0bc8c000000XcodAAC"},
    %{name: "Urología Ginecológica", id: "0bc8c000000XcoeAAC"},
    %{name: "Urología Pediátrica", id: "0bc8c000000XcofAAC"},
    %{name: "Virología", id: "0bc8c000000XcogAAC"}
  ]

  @doc "The embedded PRD catalog (ignores config). Mostly for tests/tooling."
  def default_catalog, do: @default_catalog

  @doc """
  Raw catalog entries: `[%{id: String.t(), name: String.t()}]`. Uses the
  `:medikit` `:specialty_catalog` config when it is a non-empty list, otherwise
  the embedded PRD catalog.
  """
  def catalog do
    case Application.get_env(:ledgr, :medikit, []) |> Keyword.get(:specialty_catalog) do
      list when is_list(list) and list != [] -> list
      _ -> @default_catalog
    end
  end

  @doc "`[{name, id}]` tuples for a <select> dropdown, sorted by name."
  def options do
    catalog()
    |> Enum.map(&{&1.name, &1.id})
    |> Enum.sort_by(fn {name, _id} -> name end)
  end

  @doc "True if `id` is a known catalog SpecialtyId."
  def valid_id?(id) when is_binary(id) and id != "" do
    Enum.any?(catalog(), &(&1.id == id))
  end

  def valid_id?(_), do: false

  @doc """
  Resolves a free-text specialty name (e.g. the doctor's `specialty` column) to
  a catalog `SpecialtyId`, or `nil` when there is no confident match. Matching
  is accent- and case-insensitive on the whole name, so "medicina general" and
  "Medicina General" both resolve. Used by the one-off backfill that populates
  `doctors.medikit_specialty_id`; never a substitute for the operator picking
  the specialty in the doctor form.
  """
  def resolve_id(name) when is_binary(name) do
    key = normalize(name)

    if key == "" do
      nil
    else
      Enum.find_value(catalog(), fn %{name: n, id: id} ->
        if normalize(n) == key, do: id
      end)
    end
  end

  def resolve_id(_), do: nil

  # Fold to NFD, drop combining diacritics, downcase, collapse whitespace.
  defp normalize(s) do
    s
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
