defmodule Mnesia.Ecto do
  @moduledoc """
  Mnesia adapter for Ecto.
  """

  alias Ecto.Migration.Index
  alias Ecto.Migration.Table
  alias Ecto.Query
  alias Ecto.Query.SelectExpr
  alias Mnesia.Ecto.Query, as: MnesiaQuery

  @behaviour Ecto.Adapter.Storage

  @doc false
  def storage_up(_opts) do
    :mnesia.create_schema([node])
    :mnesia.start
  end

  @doc false
  def storage_down(_opts) do
    :mnesia.stop
    :mnesia.delete_schema([node])
  end

  @behaviour Ecto.Adapter

  @doc false
  defmacro __before_compile__(_env), do: :ok

  @doc false
  def start_link(_, _) do
    {:ok, []} = Application.ensure_all_started(:mnesia_ecto)
    {:ok, self}
  end

  @doc false
  def embed_id(_), do: Ecto.UUID.generate

  @doc false
  def dump(_, value), do: {:ok, value}

  @doc false
  def load(_, value), do: {:ok, value}

  @doc false
  def prepare(:all, %Query{
      from: {table, _},
      select: %SelectExpr{expr: fields},
      wheres: wheres}) do
    {:cache, {:all, MnesiaQuery.match_spec(table, fields, wheres: wheres)}}
  end

  def prepare(:delete_all, %Query{from: {table, _}}) do
    {:cache, {:delete_all, table}}
  end

  @doc false
  def execute(_, %{select: %{expr: expr}, sources: {{table, model}}}, {:all, [{match_head, guards, result}]}, params, _, _) do
    spec = [{match_head, MnesiaQuery.resolve_params(guards, params), result}]
    rows = table |> String.to_atom |> :mnesia.dirty_select(spec)
    if expr == {:&, [], [0]} do
      rows = rows |> Enum.map(&MnesiaQuery.row2model(&1, model))
    end
    {length(rows), rows}
  end

  def execute(_, _, {:delete_all, table}, _, nil, _) do
    {:atomic, :ok} =
      table
      |> String.to_atom
      |> :mnesia.clear_table
  end

  @doc false
  def insert(repo, meta, fields, {field, :binary_id, _}, [], opts) do
    with_id = Keyword.put(fields, field, embed_id(:foo))
    insert(repo, meta, with_id, nil, [], opts)
  end

  def insert(_, %{source: {_, table}}, fields, nil, _, _) do
    row = MnesiaQuery.to_record(fields, table)
    :ok = :mnesia.dirty_write(row)
    {:ok, MnesiaQuery.to_keyword(row)}
  end

  @doc false
  def update(_, %{source: {_, table}}, _, filters, _, _, _) do
    table
    |> String.to_atom
    |> :mnesia.dirty_select(MnesiaQuery.match_spec(table, filters))
    |> case do
      [] -> {:error, :stale}
      [row] ->
        :ok = :mnesia.dirty_delete_object(row)
        {:ok, MnesiaQuery.to_keyword(row)}
    end
  end

  @doc false
  def delete(_, %{source: {_, table}}, filters, _, _) do
    table
    |> String.to_atom
    |> :mnesia.dirty_select(MnesiaQuery.match_spec(table, filters))
    |> case do
      [] -> {:error, :stale}
      [row] ->
        :ok = :mnesia.dirty_write(row)
        {:ok, MnesiaQuery.to_keyword(row)}
    end
  end

  @behaviour Ecto.Adapter.Migration

  @doc false
  def execute_ddl(repo,
                  {:create_if_not_exists, table=%Table{name: name}, columns},
                  opts) do
    unless name in :mnesia.system_info(:tables) do
      execute_ddl(repo, {:create, table, columns}, opts)
    end
  end

  def execute_ddl(_, {:create, %Table{name: name}, columns}, _) do
    fields = for {:add, field, _, _} <- columns do
      field
    end
    {:atomic, :ok} = :mnesia.create_table(name, attributes: fields)
    :ok
  end

  def execute_ddl(_, {:create, %Index{columns: columns, table: table}}, _) do
    for attr <- columns do
      {:atomic, :ok} = :mnesia.add_table_index(table, attr)
    end
  end

  @doc false
  def supports_ddl_transaction?, do: false
end
