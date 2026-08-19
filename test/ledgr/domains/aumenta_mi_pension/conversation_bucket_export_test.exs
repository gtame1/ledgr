defmodule Ledgr.Domains.AumentaMiPension.ConversationBucketExportTest do
  use ExUnit.Case, async: true

  alias Ledgr.Domains.AumentaMiPension.ConversationBucketExport, as: Export
  alias Ledgr.Domains.AumentaMiPension.ConversationBuckets.ConversationBucket

  # `conversations` / `customers` / `messages` are bot-owned and don't exist
  # in the test repo, so these exercise the pure rendering half against rows
  # shaped exactly like the ones `fetch_rows/1` selects.
  defp row(overrides \\ %{}) do
    Map.merge(
      %{
        id: "conv-1",
        created_at: ~N[2026-06-01 20:18:00],
        last_message_at: ~N[2026-06-23 10:28:00],
        status: "closed",
        funnel_stage: "terminal",
        cliente: "Chelo",
        telefono: "523317503306",
        bucket: nil,
        mensajes: 97
      },
      overrides
    )
  end

  defp bucket(flags) do
    struct!(
      %ConversationBucket{
        conversation_id: "conv-1",
        updated_at: ~U[2026-06-24 16:16:00Z]
      },
      flags
    )
  end

  defp parse(csv) do
    csv
    |> String.replace_prefix("﻿", "")
    |> String.split("\r\n", trim: true)
  end

  describe "headers/0" do
    test "carries one column per bucket, in the schema's order" do
      headers = Export.headers()
      names = Enum.map(ConversationBucket.bucket_fields(), &Atom.to_string/1)

      # Not a hardcoded list: adding a bucket to the schema must widen the
      # CSV on its own, which is the promise ConversationBucket documents.
      assert Enum.filter(headers, &(&1 in names)) == names

      # The per-bucket block sits between the summary and the notes.
      assert Enum.find_index(headers, &(&1 == "num_buckets")) <
               Enum.find_index(headers, &(&1 == hd(names)))

      assert Enum.find_index(headers, &(&1 == List.last(names))) <
               Enum.find_index(headers, &(&1 == "notas_del_caso"))
    end
  end

  describe "row/1" do
    test "joins the labels of every ticked bucket and marks its column" do
      fields = Export.row(row(%{bucket: bucket(asesoria: true, credito_pensionado: true)}))
      by_header = Enum.zip(Export.headers(), fields) |> Map.new()

      assert by_header["etiquetada"] == "sí"
      assert by_header["buckets"] == "Asesoría, Crédito Pensionado"
      assert by_header["num_buckets"] == 2
      assert by_header["asesoria"] == "X"
      assert by_header["credito_pensionado"] == "X"
      assert by_header["demanda"] == ""
      assert by_header["traspaso_afore"] == ""
    end

    test "keeps untagged conversations in the file, marked as such" do
      fields = Export.row(row())
      by_header = Enum.zip(Export.headers(), fields) |> Map.new()

      assert by_header["conversation_id"] == "conv-1"
      assert by_header["etiquetada"] == "no"
      assert by_header["buckets"] == ""
      assert by_header["num_buckets"] == 0
      assert by_header["notas_del_caso"] == nil
      assert by_header["etiquetada_el"] == nil
      assert by_header["mensajes"] == 97
    end

    test "treats a left-join miss that loads as a struct of nils as untagged" do
      fields = Export.row(row(%{bucket: %ConversationBucket{}}))
      by_header = Enum.zip(Export.headers(), fields) |> Map.new()

      assert by_header["etiquetada"] == "no"
      assert by_header["num_buckets"] == 0
    end

    test "renders timestamps in Mexico City time, not the stored UTC" do
      fields = Export.row(row(%{bucket: bucket(demanda: true)}))
      by_header = Enum.zip(Export.headers(), fields) |> Map.new()

      # CST is UTC-6: 20:18Z is 14:18 the same afternoon in Mexico City.
      assert by_header["creada"] == "2026-06-01 14:18"
      assert by_header["ultimo_mensaje"] == "2026-06-23 04:28"
      assert by_header["etiquetada_el"] == "2026-06-24 10:16"
    end
  end

  describe "render/1" do
    test "leads with the header row, BOM-prefixed for Excel" do
      csv = Export.render([])

      assert String.starts_with?(csv, "﻿")
      assert parse(csv) == [Enum.join(Export.headers(), ",")]
    end

    test "quotes operator notes that carry commas, quotes or newlines" do
      notes = ~s(el bot contestó mal, pide el NSS\ny di "no")

      csv =
        Export.render([
          row(%{bucket: bucket(asesoria: true, case_notes: notes)})
        ])

      # Embedded newline keeps the field on one logical CSV record.
      assert [_header, record] = parse(csv)
      assert record =~ ~s("el bot contestó mal, pide el NSS\ny di ""no""")

      # Multi-bucket labels are comma-joined, so that cell needs quoting too.
      csv = Export.render([row(%{bucket: bucket(asesoria: true, demanda: true)})])
      assert [_header, record] = parse(csv)
      assert record =~ ~s("Asesoría, Demanda")
    end
  end
end
