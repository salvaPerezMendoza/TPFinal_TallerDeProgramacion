defmodule Booking.ProtocolTest do
  use ExUnit.Case, async: true

  alias Booking.{Flight, Protocol}

  defp sample_flights do
    [
      Flight.new(%{
        id: "CDS101",
        airline_id: "CDS",
        origin: "AEP",
        destination: "BRC",
        departs_at: ~U[2026-07-20 08:00:00Z],
        price: 185_000,
        seat_count: 48
      }),
      Flight.new(%{
        id: "LIT112",
        airline_id: "LIT",
        origin: "COR",
        destination: "MDZ",
        departs_at: ~U[2026-07-21 14:00:00Z],
        price: 99_000,
        seat_count: 72
      })
    ]
  end

  test "list_flights devuelve un item por vuelo con la aerolínea mapeada a nombre" do
    assert %{type: "flights", flights: flights} =
             Protocol.handle(%{"type" => "list_flights"}, sample_flights())

    assert length(flights) == 2

    first = hd(flights)
    assert first.id == "CDS101"
    assert first.airline == "Cóndor del Sur"
    assert first.origin == "AEP"
    assert first.destination == "BRC"
    assert first.price == 185_000
    assert first.seat_count == 48
    assert first.departs_at == "2026-07-20T08:00:00Z"
  end

  test "list_flights sin vuelos devuelve la lista vacía" do
    assert %{type: "flights", flights: []} = Protocol.handle(%{"type" => "list_flights"}, [])
  end

  test "un mensaje desconocido devuelve error" do
    assert %{type: "error", reason: "invalid_message"} = Protocol.handle(%{"type" => "nope"}, [])
  end
end
