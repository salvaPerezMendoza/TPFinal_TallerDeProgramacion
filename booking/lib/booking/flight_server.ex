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
      viene de esa re-validación;
    * **persiste** (write-through) cada cambio de reserva en `Booking.Persistence`, de
      forma sincrónica (guarda antes de responderle al cliente). Solo si se le inyectó un
      `:persistence` (lo hace el `FlightSupervisor`); sin él es no-op;
    * **cobra** (pago simulado): `pay` lanza una `Task` supervisada (`Booking.PaymentSupervisor`)
      que duerme 1-5 s y le manda `{:payment_result, id, result}`. La Task no confirma sola; el
      proceso confirma solo si la reserva sigue `:pending` (re-validación). El timer de
      expiración sigue corriendo durante el pago, así la carrera pago-vs-expiración se resuelve
      sola. Ver docs/DECISIONES.md D7.

  Estado del proceso: `%{flight: %Booking.Flight{}, seq: pos_integer, ttl_ms: pos_integer,
  persistence: GenServer.server() | nil, timers: %{reservation_id => reference},
  payments: MapSet.t()}` (`payments` = reservas con un pago en vuelo). El dominio decide *qué*
  pasa; este módulo aporta *cuándo*, *con qué identidad* y *dónde se guarda*.
  """

  use GenServer

  alias Booking.{Flight, Persistence, Reservation}

  # --- API de cliente ---

  @doc """
  Arranca el proceso. `opts` debe incluir `:flight` (el `%Booking.Flight{}` esqueleto) y
  puede incluir `:name` (un `{:via, Registry, …}`), `:ttl_ms` (plazo de expiración; por
  defecto `Booking.Reservation.default_ttl_ms/0`), `:persistence` (server de
  `Booking.Persistence` para el write-through; por defecto `nil` = no persiste) y
  `:reservations` (reservas persistidas a reconstruir en el `init`; por defecto `[]`).
  """
  def start_link(opts) do
    {flight, opts} = Keyword.pop!(opts, :flight)
    {ttl_ms, opts} = Keyword.pop(opts, :ttl_ms, Reservation.default_ttl_ms())
    {persistence, opts} = Keyword.pop(opts, :persistence, nil)
    {reservations, opts} = Keyword.pop(opts, :reservations, [])
    GenServer.start_link(__MODULE__, {flight, ttl_ms, persistence, reservations}, opts)
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

  @doc """
  Inicia el pago simulado de una reserva pendiente: lanza una `Task` supervisada que, tras
  1-5 s, le manda el resultado al `FlightServer` (que confirma si la reserva sigue pendiente).
  Devuelve `{:ok, :processing}` (es asíncrono). `opts` admite `:force` (`:ok`/`:error`) y
  `:delay` (ms) para tests.
  """
  @spec pay(GenServer.server(), String.t(), keyword()) ::
          {:ok, :processing}
          | {:error, :reservation_not_found | :not_pending | :payment_in_progress}
  def pay(server, reservation_id, opts \\ []) do
    GenServer.call(server, {:pay, reservation_id, opts})
  end

  @doc "Devuelve el `%Booking.Flight{}` actual (inspección / detalle del vuelo)."
  @spec get_flight(GenServer.server()) :: Flight.t()
  def get_flight(server), do: GenServer.call(server, :get_flight)

  # --- Callbacks ---

  @impl true
  def init({%Flight{} = flight, ttl_ms, persistence, reservations}) do
    now = DateTime.utc_now()
    {flight, arms, expired} = Flight.load(flight, reservations, now)

    # Re-arma los timers de las :pending vigentes por su tiempo restante (expires_at - now).
    timers =
      Map.new(arms, fn {reservation_id, remaining_ms} ->
        {reservation_id, Process.send_after(self(), {:expire, reservation_id}, remaining_ms)}
      end)

    state = %{
      flight: flight,
      seq: next_seq(reservations),
      ttl_ms: ttl_ms,
      persistence: persistence,
      timers: timers,
      payments: MapSet.new()
    }

    # Las :pending ya vencidas se reconstruyeron como :expired → persistir esa corrección.
    Enum.each(expired, fn reservation -> persist(state, reservation) end)

    {:ok, state}
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

        persist(state, reservation)
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
  def handle_call({:pay, reservation_id, opts}, _from, state) do
    case Map.get(state.flight.reservations, reservation_id) do
      %Reservation{status: :pending} ->
        if MapSet.member?(state.payments, reservation_id) do
          # Doble-pay: ya hay una Task de pago en vuelo para esta reserva.
          {:reply, {:error, :payment_in_progress}, state}
        else
          start_payment_task(self(), reservation_id, opts)
          state = %{state | payments: MapSet.put(state.payments, reservation_id)}
          {:reply, {:ok, :processing}, state}
        end

      nil ->
        {:reply, {:error, :reservation_not_found}, state}

      %Reservation{} ->
        {:reply, {:error, :not_pending}, state}
    end
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
      {:ok, %Flight{} = flight} ->
        state = %{state | flight: flight}
        persist(state, Map.fetch!(flight.reservations, reservation_id))
        {:noreply, state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:payment_result, reservation_id, result}, state) do
    state = %{state | payments: MapSet.delete(state.payments, reservation_id)}
    {:noreply, apply_payment(result, reservation_id, state)}
  end

  # Pago aprobado: confirma SOLO si la reserva sigue :pending. Si entre el inicio del pago y
  # este resultado la reserva expiró/canceló, Flight.confirm devuelve {:error, :not_pending} y
  # el pago tardío es no-op (así se resuelve la carrera pago-vs-expiración).
  defp apply_payment(:ok, reservation_id, state) do
    case Flight.confirm(state.flight, reservation_id) do
      {:ok, %Flight{} = flight} ->
        {_reservation, state} = apply_ok(flight, reservation_id, state)
        state

      {:error, _reason} ->
        state
    end
  end

  # Pago rechazado: la reserva sigue :pending (su timer sigue corriendo hasta vencer).
  defp apply_payment(:error, _reservation_id, state), do: state

  # Lanza la Task supervisada que simula el pago: duerme `delay` y manda el resultado de
  # vuelta. El resultado se decide acá (force en tests, o random según payment_success_rate
  # en prod); la Task NO confirma, solo avisa.
  defp start_payment_task(flight_server, reservation_id, opts) do
    delay = Keyword.get(opts, :delay, Enum.random(1000..5000))
    result = Keyword.get(opts, :force) || payment_result()

    Task.Supervisor.start_child(Booking.PaymentSupervisor, fn ->
      Process.sleep(delay)
      send(flight_server, {:payment_result, reservation_id, result})
    end)
  end

  defp payment_result do
    if :rand.uniform() <= Application.get_env(:booking, :payment_success_rate, 1.0),
      do: :ok,
      else: :error
  end

  # Traduce el resultado de una transición pura (confirm/cancel) a la respuesta del cliente.
  defp reply_transition({:ok, %Flight{} = flight}, reservation_id, state) do
    {reservation, state} = apply_ok(flight, reservation_id, state)
    {:reply, {:ok, reservation}, state}
  end

  defp reply_transition({:error, reason}, _reservation_id, state) do
    {:reply, {:error, reason}, state}
  end

  # Aplica una confirmación/cancelación exitosa al estado: guarda el vuelo, cancela el timer
  # de la reserva (optimización) y persiste. Devuelve {reservation, new_state}. Lo comparten
  # confirm/cancel (vía reply_transition) y el resultado de un pago aprobado.
  defp apply_ok(%Flight{} = flight, reservation_id, state) do
    reservation = Map.fetch!(flight.reservations, reservation_id)
    state = %{state | flight: flight, timers: cancel_timer(state.timers, reservation_id)}
    persist(state, reservation)
    {reservation, state}
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

  # Write-through sincrónico: guarda la reserva en el backend ANTES de responderle al
  # cliente. Sin backend configurado (:persistence nil) es no-op.
  defp persist(%{persistence: nil}, _reservation), do: :ok

  defp persist(%{persistence: persistence}, %Reservation{} = reservation) do
    Persistence.put_reservation(reservation, persistence)
  end

  # Próximo número de id de reserva: max(n) + 1 sobre los sufijos "-r<n>" de las reservas
  # persistidas, para que los ids nuevos no colisionen con los ya emitidos (D5).
  defp next_seq(reservations) do
    reservations
    |> Enum.map(fn %{id: id} ->
      case id |> String.split("-r") |> List.last() |> Integer.parse() do
        {n, _rest} -> n
        :error -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end
end
