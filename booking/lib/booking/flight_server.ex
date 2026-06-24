defmodule Booking.FlightServer do
  @moduledoc """
  Proceso (GenServer) dueño de **un** vuelo. Es la "cáscara con efectos" alrededor del
  dominio puro `Booking.Flight`:

    * **genera los efectos** que el dominio a propósito no tiene: el `reservation_id`
      (contador `"<flight_id>-r<n>"`, ver docs/DECISIONES.md D5) y el `now` del reloj;
    * **serializa** las operaciones del vuelo: como todas entran por `GenServer.call`,
      el proceso las atiende de a una desde su mailbox. De ahí sale la garantía de
      "un solo ganador por asiento" cuando varios usuarios compiten al mismo tiempo;
    * **expira** las reservas: al reservar programa `Process.send_after(self(),
      {:expire, id}, ttl_ms)`. `handle_info/2` re-valida con `Flight.expire/2`, que solo
      transiciona si la reserva sigue `:pending` (sobre una ya finalizada es no-op). Por
      eso cancelar el timer al confirmar/cancelar es solo una optimización: la corrección
      viene de esa re-validación.

  Estado del proceso: `%{flight: %Booking.Flight{}, seq: pos_integer, ttl_ms: pos_integer,
  timers: %{reservation_id => reference}}`. El dominio decide *qué* pasa; este módulo
  aporta *cuándo* y *con qué identidad*, y guarda el resultado.
  """

  use GenServer

  alias Booking.{Flight, Reservation}

  # --- API de cliente ---

  @doc """
  Arranca el proceso. `opts` debe incluir `:flight` (el `%Booking.Flight{}` inicial) y
  puede incluir `:name` (un `{:via, Registry, …}`) y `:ttl_ms` (plazo de expiración de
  las reservas; por defecto `Booking.Reservation.default_ttl_ms/0`).
  """
  def start_link(opts) do
    {flight, opts} = Keyword.pop!(opts, :flight)
    {ttl_ms, opts} = Keyword.pop(opts, :ttl_ms, Reservation.default_ttl_ms())
    GenServer.start_link(__MODULE__, {flight, ttl_ms}, opts)
  end

  @doc "Inicia una reserva pendiente sobre `seat_id` para `user_id`."
  @spec reserve_seat(GenServer.server(), String.t(), String.t()) ::
          {:ok, Reservation.t()} | {:error, :seat_not_found | :seat_taken}
  def reserve_seat(server, seat_id, user_id) do
    GenServer.call(server, {:reserve_seat, seat_id, user_id})
  end

  @doc "Confirma (paga) una reserva pendiente."
  @spec confirm(GenServer.server(), String.t()) ::
          {:ok, Reservation.t()} | {:error, :reservation_not_found | :not_pending}
  def confirm(server, reservation_id) do
    GenServer.call(server, {:confirm, reservation_id})
  end

  @doc "Cancela una reserva pendiente."
  @spec cancel(GenServer.server(), String.t()) ::
          {:ok, Reservation.t()} | {:error, :reservation_not_found | :not_pending}
  def cancel(server, reservation_id) do
    GenServer.call(server, {:cancel, reservation_id})
  end

  @doc "Devuelve el `%Booking.Flight{}` actual (inspección / detalle del vuelo)."
  @spec get_flight(GenServer.server()) :: Flight.t()
  def get_flight(server), do: GenServer.call(server, :get_flight)

  # --- Callbacks ---

  @impl true
  def init({%Flight{} = flight, ttl_ms}) do
    {:ok, %{flight: flight, seq: 1, ttl_ms: ttl_ms, timers: %{}}}
  end

  @impl true
  def handle_call({:reserve_seat, seat_id, user_id}, _from, state) do
    reservation_id = "#{state.flight.id}-r#{state.seq}"
    now = DateTime.utc_now()

    case Flight.reserve_seat(state.flight, seat_id, user_id, reservation_id, now, state.ttl_ms) do
      {:ok, {flight, reservation}} ->
        # Programa la expiración: el proceso se manda {:expire, id} a sí mismo dentro de
        # ttl_ms y guarda el timer_ref para poder cancelarlo si se confirma/cancela antes.
        timer_ref = Process.send_after(self(), {:expire, reservation_id}, state.ttl_ms)

        state = %{
          state
          | flight: flight,
            seq: state.seq + 1,
            timers: Map.put(state.timers, reservation_id, timer_ref)
        }

        {:reply, {:ok, reservation}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:confirm, reservation_id}, _from, state) do
    reply_transition(Flight.confirm(state.flight, reservation_id), reservation_id, state)
  end

  @impl true
  def handle_call({:cancel, reservation_id}, _from, state) do
    reply_transition(Flight.cancel(state.flight, reservation_id), reservation_id, state)
  end

  @impl true
  def handle_call(:get_flight, _from, state) do
    {:reply, state.flight, state}
  end

  @impl true
  def handle_info({:expire, reservation_id}, state) do
    # Saca el timer del estado (ya disparó) para no acumular refs viejos.
    state = %{state | timers: Map.delete(state.timers, reservation_id)}

    # RE-VALIDA en el dominio: expire/2 solo transiciona si la reserva sigue :pending.
    # Si ya estaba confirmada/cancelada (o el timer disparó tarde), es no-op. De ahí que
    # la corrección no dependa de haber cancelado el timer.
    case Flight.expire(state.flight, reservation_id) do
      {:ok, %Flight{} = flight} -> {:noreply, %{state | flight: flight}}
      {:error, _reason} -> {:noreply, state}
    end
  end

  # Traduce el resultado de una transición pura (confirm/cancel) a la respuesta del
  # cliente: en éxito guarda el vuelo nuevo, cancela el timer de expiración (optimización)
  # y devuelve la reserva actualizada.
  defp reply_transition({:ok, %Flight{} = flight}, reservation_id, state) do
    reservation = Map.fetch!(flight.reservations, reservation_id)
    state = %{state | flight: flight, timers: cancel_timer(state.timers, reservation_id)}
    {:reply, {:ok, reservation}, state}
  end

  defp reply_transition({:error, reason}, _reservation_id, state) do
    {:reply, {:error, reason}, state}
  end

  # Cancela el timer de una reserva (si existe) y lo saca del estado. Es una optimización:
  # aunque el timer ya hubiera disparado (cancel_timer devuelve false), el {:expire} que
  # llegue se re-valida en handle_info y resulta no-op.
  defp cancel_timer(timers, reservation_id) do
    case Map.pop(timers, reservation_id) do
      {nil, timers} ->
        timers

      {timer_ref, timers} ->
        Process.cancel_timer(timer_ref)
        timers
    end
  end
end
