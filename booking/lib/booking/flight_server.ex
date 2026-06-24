defmodule Booking.FlightServer do
  @moduledoc """
  Proceso (GenServer) dueño de **un** vuelo. Es la "cáscara con efectos" alrededor del
  dominio puro `Booking.Flight`:

    * **genera los efectos** que el dominio a propósito no tiene: el `reservation_id`
      (contador `"<flight_id>-r<n>"`, ver docs/DECISIONES.md D5) y el `now` del reloj;
    * **serializa** las operaciones del vuelo: como todas entran por `GenServer.call`,
      el proceso las atiende de a una desde su mailbox. De ahí sale la garantía de
      "un solo ganador por asiento" cuando varios usuarios compiten al mismo tiempo.

  El estado del proceso es `%{flight: %Booking.Flight{}, seq: pos_integer}` (`seq` es el
  contador de ids). El dominio decide *qué* pasa; este módulo aporta *cuándo* y *con qué
  identidad*, y guarda el resultado.
  """

  use GenServer

  alias Booking.{Flight, Reservation}

  # --- API de cliente ---

  @doc """
  Arranca el proceso. `opts` debe incluir `:flight` (el `%Booking.Flight{}` inicial) y
  puede incluir `:name` (en el sub-paso 2 será un `{:via, Registry, …}`).
  """
  def start_link(opts) do
    {flight, opts} = Keyword.pop!(opts, :flight)
    GenServer.start_link(__MODULE__, flight, opts)
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
  def init(%Flight{} = flight) do
    {:ok, %{flight: flight, seq: 1}}
  end

  @impl true
  def handle_call({:reserve_seat, seat_id, user_id}, _from, state) do
    reservation_id = "#{state.flight.id}-r#{state.seq}"
    now = DateTime.utc_now()

    case Flight.reserve_seat(state.flight, seat_id, user_id, reservation_id, now) do
      {:ok, {flight, reservation}} ->
        {:reply, {:ok, reservation}, %{state | flight: flight, seq: state.seq + 1}}

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

  # Traduce el resultado de una transición pura (confirm/cancel) a la respuesta del
  # cliente: en éxito guarda el vuelo nuevo y devuelve la reserva actualizada.
  defp reply_transition({:ok, %Flight{} = flight}, reservation_id, state) do
    reservation = Map.fetch!(flight.reservations, reservation_id)
    {:reply, {:ok, reservation}, %{state | flight: flight}}
  end

  defp reply_transition({:error, reason}, _reservation_id, state) do
    {:reply, {:error, reason}, state}
  end
end
