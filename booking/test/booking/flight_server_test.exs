defmodule Booking.FlightServerTest do
  use ExUnit.Case, async: true

  alias Booking.{Flight, FlightServer}

  # Arranca un FlightServer supervisado por el test (se limpia solo al terminar).
  defp start_server(seat_count \\ 20) do
    flight =
      Flight.new(%{
        id: "AR1001",
        airline_id: "condor",
        origin: "AEP",
        destination: "BRC",
        departs_at: ~U[2026-07-20 08:30:00Z],
        price: 185_000,
        seat_count: seat_count
      })

    start_supervised!({FlightServer, flight: flight})
  end

  test "reservar a través del server marca el asiento y devuelve la reserva pendiente" do
    server = start_server()

    assert {:ok, reservation} = FlightServer.reserve_seat(server, "1", "ana")
    assert reservation.status == :pending
    assert reservation.seat_id == "1"
    assert reservation.user_id == "ana"
    assert reservation.id == "AR1001-r1"
    assert FlightServer.get_flight(server).seats["1"].status == :reserved
  end

  test "el server genera ids de reserva incrementales" do
    server = start_server()

    {:ok, r1} = FlightServer.reserve_seat(server, "1", "ana")
    {:ok, r2} = FlightServer.reserve_seat(server, "2", "ana")

    assert r1.id == "AR1001-r1"
    assert r2.id == "AR1001-r2"
  end

  test "confirmar deja el asiento ocupado; cancelar lo libera (a través del server)" do
    server = start_server()

    {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
    assert {:ok, confirmed} = FlightServer.confirm(server, res.id)
    assert confirmed.status == :confirmed
    assert FlightServer.get_flight(server).seats["1"].status == :confirmed

    {:ok, res2} = FlightServer.reserve_seat(server, "2", "ana")
    assert {:ok, cancelled} = FlightServer.cancel(server, res2.id)
    assert cancelled.status == :cancelled
    assert FlightServer.get_flight(server).seats["2"].status == :free
  end

  test "reservar un asiento ya ocupado falla" do
    server = start_server()
    {:ok, _} = FlightServer.reserve_seat(server, "1", "ana")

    assert {:error, :seat_taken} = FlightServer.reserve_seat(server, "1", "beto")
  end

  test "100 usuarios piden el mismo asiento a la vez: gana exactamente uno" do
    server = start_server()

    # Este test demuestra la SERIALIZACIÓN del GenServer: lanzamos 100 pedidos del mismo
    # asiento "en paralelo", pero el FlightServer atiende su mailbox de a un mensaje por
    # vez, así que solo el primero ve el asiento libre. Aunque las 100 llamadas "lleguen
    # juntas", gana exactamente 1 y los otros 99 reciben :seat_taken. Sin locks.
    results =
      1..100
      |> Task.async_stream(
        fn i -> FlightServer.reserve_seat(server, "1", "user_#{i}") end,
        max_concurrency: 100,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    winners = Enum.filter(results, &match?({:ok, _}, &1))
    losers = Enum.filter(results, &match?({:error, :seat_taken}, &1))

    assert length(winners) == 1
    assert length(losers) == 99
    assert FlightServer.get_flight(server).seats["1"].status == :reserved
  end
end
