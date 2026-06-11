defmodule Ledgr.Domains.AumentaMiPension.ConversationBuckets do
  @moduledoc """
  Context for the Ledgr-owned conversation tags ("buckets") overlay
  (`conversation_buckets` table). One row per conversation, six boolean
  flags ticked by operators from the checkbox card on the conversation
  detail page. The bot never writes here.

  See `ConversationBucket` for the bucket fields and their Spanish labels.
  """

  alias Ledgr.Domains.AumentaMiPension.ConversationBuckets.ConversationBucket
  alias Ledgr.Repo

  @doc """
  Returns the bucket row for `conversation_id`, or nil if the
  conversation has never been tagged.
  """
  def get(conversation_id) when is_binary(conversation_id) do
    Repo.get(ConversationBucket, conversation_id)
  end

  def get(_), do: nil

  @doc """
  Inserts or updates the bucket row for `conversation_id` from form
  attrs (string keys, e.g. `%{"asesoria" => "true", "demanda" => "false"}`).

  The checkbox card submits all six flags on every change (each checkbox
  is backed by a hidden `false` input), so unticking a box reliably
  clears it. Returns `{:ok, bucket}` or `{:error, changeset}`.
  """
  def upsert(conversation_id, attrs) when is_binary(conversation_id) and is_map(attrs) do
    bucket = Repo.get(ConversationBucket, conversation_id) || %ConversationBucket{}

    bucket
    |> ConversationBucket.changeset(Map.put(attrs, "conversation_id", conversation_id))
    |> Repo.insert_or_update()
  end
end
