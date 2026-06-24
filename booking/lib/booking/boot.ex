defmodule Booking.Boot do
  @moduledoc """
  Orquestador de arranque (restore). Lo llama `Booking.Application.start/2` **después** de
  levantar el árbol de supervisión: relee de `Booking.Persistence` los vuelos y reservas
  persistidos y levanta un `FlightServer` por vuelo con sus reservas.

  Lee DETS **una sola vez** (`get_flights` + `get_reservations`) y agrupa las reservas por
  vuelo en memoria, en vez de que cada `FlightServer` escanee toda la tabla de reservas.

  - Primer boot (DETS vacío) → no levanta nada: la app arranca vacía y el seed la puebla más
    tarde con `Booking.FlightSupervisor.create_flight/1`.
  - Boot con datos → restaura cada vuelo con su estado.
  """

  alias Booking.{FlightSupervisor, Persistence}

  @doc "Relee los vuelos persistidos y levanta un FlightServer por cada uno con sus reservas."
  @spec restore() :: :ok
  def restore do
    reservations_by_flight = Enum.group_by(Persistence.get_reservations(), & &1.flight_id)

    Enum.each(Persistence.get_flights(), fn flight ->
      FlightSupervisor.start_flight(flight, Map.get(reservations_by_flight, flight.id, []))
    end)
  end
end
