defmodule Booking.Persistence do
  @moduledoc """
  Proceso (GenServer) **único dueño** de las tablas DETS del sistema (`users`, `flights`,
  `reservations`). Todos los demás procesos leen y escriben **a través de él**, por mensajes.

  DETS (*Disk-based ETS*) son tablas clave→valor de Erlang persistidas en un archivo; como
  ETS pero en disco, así sobreviven al reinicio de la VM. No es buena idea que varios
  procesos toquen el mismo archivo a la vez (riesgo de corrupción), por eso un único dueño:
  **serializa** todas las escrituras (una por vez), evita locks y separa la infraestructura
  (E/S) del dominio. Ver docs/DECISIONES.md (D6).

  `start_link/1` acepta `:name` (default `#{inspect(__MODULE__)}`) y `:dir` (carpeta de los
  archivos `.dets`, default `Application.get_env(:booking, :data_dir, "data")`). Esos
  parámetros permiten levantar instancias **aisladas** en los tests.
  """

  use GenServer

  @kinds [:users, :flights, :reservations]

  # --- API de cliente (el server va último, con default, para poder usar el singleton) ---

  def put_user(user, server \\ __MODULE__), do: put(server, :users, user)
  def get_users(server \\ __MODULE__), do: all(server, :users)

  def put_flight(flight, server \\ __MODULE__), do: put(server, :flights, flight)
  def get_flights(server \\ __MODULE__), do: all(server, :flights)

  def put_reservation(reservation, server \\ __MODULE__),
    do: put(server, :reservations, reservation)

  def get_reservations(server \\ __MODULE__), do: all(server, :reservations)

  defp put(server, kind, %{id: id} = value), do: GenServer.call(server, {:put, kind, id, value})
  defp all(server, kind), do: GenServer.call(server, {:all, kind})

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    dir = Keyword.get(opts, :dir, Application.get_env(:booking, :data_dir, "data"))
    File.mkdir_p!(dir)

    # Una tabla DETS por tipo. El nombre de tabla se deriva del `name` de la instancia para
    # que dos Persistence (p. ej. en tests) no compartan tabla; el archivo va bajo `dir`.
    tables =
      Map.new(@kinds, fn kind ->
        table = :"#{name}.#{kind}"
        file = dir |> Path.join("#{kind}.dets") |> String.to_charlist()
        {:ok, ^table} = :dets.open_file(table, file: file, type: :set)
        {kind, table}
      end)

    {:ok, %{tables: tables}}
  end

  @impl true
  def handle_call({:put, kind, id, value}, _from, state) do
    :ok = :dets.insert(state.tables[kind], {id, value})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:all, kind}, _from, state) do
    values = :dets.foldl(fn {_id, value}, acc -> [value | acc] end, [], state.tables[kind])
    {:reply, values, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cierra las tablas para que DETS haga flush del archivo a disco.
    Enum.each(state.tables, fn {_kind, table} -> :dets.close(table) end)
    :ok
  end
end
