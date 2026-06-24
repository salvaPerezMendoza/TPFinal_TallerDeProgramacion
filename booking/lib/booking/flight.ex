defmodule Booking.Flight do
  @moduledoc """
  Vuelo: agregado dueño del estado dinámico (asientos y reservas) que hace cumplir
  las invariantes del dominio.

  Todas las funciones son **puras**: dado un vuelo devuelven uno nuevo (o un error),
  sin efectos secundarios ni estado compartido. Las operaciones que pueden fallar
  devuelven `{:ok, _}` | `{:error, motivo}`.

  El tiempo (`now`) y el identificador de reserva se reciben por parámetro para que
  las transiciones sean deterministas y fáciles de testear; la generación de ids y
  los timers de expiración son responsabilidad del proceso (FlightServer, Etapa 3).

  Invariantes que se preservan:

    * un asiento no puede estar reservado/confirmado por dos reservas a la vez;
    * solo una reserva `:pending` puede confirmarse, cancelarse o expirar;
    * confirmar deja el asiento ocupado; cancelar o expirar lo liberan.
  """

  alias Booking.{Reservation, Seat}

  @enforce_keys [:id, :airline_id, :origin, :destination, :departs_at, :price]
  defstruct [
    :id,
    :airline_id,
    :origin,
    :destination,
    :departs_at,
    :price,
    seats: %{},
    reservations: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          airline_id: String.t(),
          origin: String.t(),
          destination: String.t(),
          departs_at: DateTime.t(),
          price: non_neg_integer(),
          seats: %{optional(String.t()) => Seat.t()},
          reservations: %{optional(String.t()) => Reservation.t()}
        }

  @doc """
  Crea un vuelo con `seat_count` asientos libres, numerados `"1"`..`"N"`.

  `attrs` es un mapa con `:id`, `:airline_id`, `:origin`, `:destination`,
  `:departs_at`, `:price` y `:seat_count` (entre 20 y 100, según el enunciado).
  La cantidad de asientos queda implícita en el mapa `seats` (no se guarda aparte).
  """
  @spec new(map()) :: t()
  def new(%{seat_count: seat_count} = attrs) when seat_count in 20..100 do
    seats =
      Map.new(1..seat_count, fn n ->
        id = Integer.to_string(n)
        {id, Seat.new(id)}
      end)

    attrs =
      attrs
      |> Map.delete(:seat_count)
      |> Map.put(:seats, seats)

    struct!(__MODULE__, attrs)
  end

  @doc """
  Inicia una reserva pendiente sobre `seat_id` para `user_id`.

    * `{:ok, {flight, reservation}}` si el asiento estaba libre.
    * `{:error, :seat_not_found}` si el asiento no existe.
    * `{:error, :seat_taken}` si ya está reservado o confirmado (lo ganó otro).
  """
  @spec reserve_seat(t(), String.t(), String.t(), String.t(), DateTime.t()) ::
          {:ok, {t(), Reservation.t()}} | {:error, :seat_not_found | :seat_taken}
  def reserve_seat(%__MODULE__{} = flight, seat_id, user_id, reservation_id, %DateTime{} = now) do
    case Map.get(flight.seats, seat_id) do
      nil ->
        {:error, :seat_not_found}

      %Seat{status: :free} = seat ->
        reservation = Reservation.new(reservation_id, flight.id, seat_id, user_id, now)
        seat = %Seat{seat | status: :reserved, held_by: reservation_id}
        flight = put_reservation_and_seat(flight, reservation, seat)
        {:ok, {flight, reservation}}

      %Seat{} ->
        {:error, :seat_taken}
    end
  end

  @doc """
  Confirma (paga) una reserva pendiente: la reserva pasa a `:confirmed` y el asiento
  queda ocupado de forma definitiva.

    * `{:error, :reservation_not_found}` si la reserva no existe.
    * `{:error, :not_pending}` si ya no está pendiente (un pago tardío no confirma
      una reserva expirada o cancelada).
  """
  @spec confirm(t(), String.t()) :: {:ok, t()} | {:error, :reservation_not_found | :not_pending}
  def confirm(%__MODULE__{} = flight, reservation_id) do
    with_pending_reservation(flight, reservation_id, fn %Reservation{} = reservation ->
      reservation = %Reservation{reservation | status: :confirmed}
      seat = occupy_seat(seat_of(flight, reservation))
      put_reservation_and_seat(flight, reservation, seat)
    end)
  end

  @doc """
  Cancela una reserva pendiente (decisión del usuario): la reserva pasa a
  `:cancelled` y el asiento se libera. Mismos errores que `confirm/2`.
  """
  @spec cancel(t(), String.t()) :: {:ok, t()} | {:error, :reservation_not_found | :not_pending}
  def cancel(%__MODULE__{} = flight, reservation_id) do
    with_pending_reservation(flight, reservation_id, fn %Reservation{} = reservation ->
      reservation = %Reservation{reservation | status: :cancelled}
      seat = free_seat(seat_of(flight, reservation))
      put_reservation_and_seat(flight, reservation, seat)
    end)
  end

  @doc """
  Expira una reserva pendiente (venció el minuto sin confirmar): la reserva pasa a
  `:expired` y el asiento se libera. El *cuándo* lo decide el proceso (FlightServer);
  acá solo se aplica el cambio de estado. Mismos errores que `confirm/2`.
  """
  @spec expire(t(), String.t()) :: {:ok, t()} | {:error, :reservation_not_found | :not_pending}
  def expire(%__MODULE__{} = flight, reservation_id) do
    with_pending_reservation(flight, reservation_id, fn %Reservation{} = reservation ->
      reservation = %Reservation{reservation | status: :expired}
      seat = free_seat(seat_of(flight, reservation))
      put_reservation_and_seat(flight, reservation, seat)
    end)
  end

  # --- Auxiliares privados ---

  # Aplica `fun` solo si la reserva existe y está pendiente. Centraliza la regla
  # "solo una reserva :pending puede transicionar" que comparten confirm/cancel/expire.
  defp with_pending_reservation(flight, reservation_id, fun) do
    case Map.get(flight.reservations, reservation_id) do
      nil -> {:error, :reservation_not_found}
      %Reservation{status: :pending} = reservation -> {:ok, fun.(reservation)}
      %Reservation{} -> {:error, :not_pending}
    end
  end

  defp seat_of(flight, %Reservation{seat_id: seat_id}) do
    %Seat{} = Map.fetch!(flight.seats, seat_id)
  end

  defp occupy_seat(%Seat{} = seat), do: %Seat{seat | status: :confirmed}

  defp free_seat(%Seat{} = seat), do: %Seat{seat | status: :free, held_by: nil}

  defp put_reservation_and_seat(
         %__MODULE__{} = flight,
         %Reservation{} = reservation,
         %Seat{} = seat
       ) do
    %__MODULE__{
      flight
      | reservations: Map.put(flight.reservations, reservation.id, reservation),
        seats: Map.put(flight.seats, seat.id, seat)
    }
  end
end
