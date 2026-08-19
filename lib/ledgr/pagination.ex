defmodule Ledgr.Pagination do
  @moduledoc """
  Offset pagination for the index pages.

  Before this existed the conversation lists ran `Repo.all` over the whole
  filtered table and then preloaded two associations onto every row, so one
  request's peak memory grew with the table. On a 512 MB box that is the
  single largest thing a user can trigger repeatedly.

  Offset rather than keyset: operators jump to a page and want a total, and
  `COUNT(*)` over these tables is cheap. `Conversations.neighbors/2` already
  does keyset navigation for the prev/next links on the detail page, which is
  where ordering stability actually matters.

  Preloads are applied to the page, never to the query — preloading first is
  what made the old code expensive.
  """

  import Ecto.Query

  alias Ledgr.Repo

  @default_page_size 50
  @max_page_size 200

  defstruct entries: [],
            page: 1,
            page_size: @default_page_size,
            total: 0,
            total_pages: 1

  @type t :: %__MODULE__{
          entries: list(),
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer(),
          total_pages: pos_integer()
        }

  @doc """
  Runs `query` for one page and returns a `%Ledgr.Pagination{}`.

  Options:

    * `:page` — 1-based; accepts an integer or a string straight from params.
      Out-of-range values clamp to the first or last page rather than
      returning an empty list, so a stale bookmark still shows something.
    * `:page_size` — defaults to #{@default_page_size}, capped at #{@max_page_size}.
    * `:preload` — applied to the page's rows after loading them.
  """
  def paginate(query, opts \\ []) do
    page_size = normalize_page_size(opts[:page_size])
    total = count(query)
    total_pages = max(1, ceil(total / page_size))
    page = normalize_page(opts[:page], total_pages)

    entries =
      query
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()
      |> maybe_preload(opts[:preload])

    %__MODULE__{
      entries: entries,
      page: page,
      page_size: page_size,
      total: total,
      total_pages: total_pages
    }
  end

  @doc """
  The 1-based index of the first and last row on the current page, for the
  "N–M of T" label. Both are 0 when there are no rows at all.
  """
  def range(%__MODULE__{total: 0}), do: {0, 0}

  def range(%__MODULE__{} = p) do
    first = (p.page - 1) * p.page_size + 1
    {first, min(first + length(p.entries) - 1, p.total)}
  end

  def default_page_size, do: @default_page_size

  # Counting has to survive a grouped query (Escuela de Dinero groups by
  # conversation to count messages), where `Repo.aggregate(:count)` on the
  # query itself would raise. Wrapping in a subquery is correct for both
  # shapes. Ordering and preloads are irrelevant to a count and only slow
  # it down.
  defp count(query) do
    query
    |> exclude(:order_by)
    |> exclude(:preload)
    |> exclude(:limit)
    |> exclude(:offset)
    |> subquery()
    |> Repo.aggregate(:count)
  end

  defp maybe_preload(entries, nil), do: entries
  defp maybe_preload(entries, []), do: entries
  defp maybe_preload(entries, preload), do: Repo.preload(entries, preload)

  defp normalize_page_size(nil), do: @default_page_size

  defp normalize_page_size(size) when is_integer(size) and size > 0,
    do: min(size, @max_page_size)

  defp normalize_page_size(_), do: @default_page_size

  defp normalize_page(page, total_pages) do
    page
    |> to_positive_integer()
    |> min(total_pages)
    |> max(1)
  end

  defp to_positive_integer(n) when is_integer(n) and n > 0, do: n

  defp to_positive_integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp to_positive_integer(_), do: 1
end
