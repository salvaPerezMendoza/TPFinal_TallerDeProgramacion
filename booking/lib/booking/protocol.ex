defmodule Booking.Protocol do
  @moduledoc """
  Lógica del protocolo WebSocket: traduce un **mensaje decodificado** (mapa con claves string)
  a una **respuesta** (mapa que el handler serializa a JSON). Es pura y testeable, separada de
  los callbacks de Cowboy (mismo corte dominio/cáscara del resto del backend).

  Ver el contrato de mensajes en `docs/protocolo.md`.
  """

  alias Booking.{Flight, Seed}

  @doc """
  Despacha un mensaje. `flights` es la lista de vuelos a mostrar (la inyecta el handler desde
  Persistence), así esta función no depende de procesos.
  """
  @spec handle(map(), [Flight.t()]) :: map()
  def handle(%{"type" => "list_flights"}, flights) do
    airline_names = Map.new(Seed.airlines())
    %{type: "flights", flights: Enum.map(flights, &flight_json(&1, airline_names))}
  end

  def handle(_message, _flights) do
    %{type: "error", reason: "invalid_message"}
  end

  defp flight_json(%Flight{} = flight, airline_names) do
    %{
      id: flight.id,
      airline: Map.get(airline_names, flight.airline_id, flight.airline_id),
      origin: flight.origin,
      destination: flight.destination,
      departs_at: DateTime.to_iso8601(flight.departs_at),
      price: flight.price,
      seat_count: map_size(flight.seats)
    }
  end
end
