defmodule Booking.Protocol do
  @moduledoc """
  Lógica del protocolo WebSocket: traduce un **mensaje decodificado** (mapa con claves string)
  a una **respuesta** y a un **contexto** de conexión actualizado. Es la parte testeable,
  separada de los callbacks de Cowboy (mismo corte dominio/cáscara del resto del backend).

  El `context` lleva el estado por-conexión (`user_id`, `flight_id`) y las **dependencias
  inyectables** (`persistence` y `lookup`: `flight_id -> {:ok, pid} | :error`), así el handler
  usa los módulos reales y los tests, instancias aisladas. Ver el contrato en
  `docs/protocolo.md`.
  """

  alias Booking.{Flight, FlightServer, Persistence, Reservation, Seed, User}

  @type context :: %{
          user_id: String.t() | nil,
          flight_id: String.t() | nil,
          persistence: GenServer.server(),
          lookup: (String.t() -> {:ok, pid()} | :error)
        }

  @doc "Despacha un mensaje. Devuelve `{respuesta, contexto_actualizado}`."
  @spec handle(map(), context()) :: {map(), context()}

  def handle(%{"type" => "register", "name" => name}, ctx) do
    user = find_or_create_user(ctx.persistence, name)
    {%{type: "registered", user_id: user.id, name: user.name}, %{ctx | user_id: user.id}}
  end

  def handle(%{"type" => "list_flights"}, ctx) do
    airline_names = Map.new(Seed.airlines())
    flights = Enum.map(Persistence.get_flights(ctx.persistence), &flight_json(&1, airline_names))
    {%{type: "flights", flights: flights}, ctx}
  end

  def handle(%{"type" => "open_flight", "flight_id" => flight_id}, ctx) do
    case ctx.lookup.(flight_id) do
      {:ok, pid} ->
        flight = FlightServer.get_flight(pid)

        response = %{
          type: "flight_detail",
          flight: flight_summary(flight),
          seats: seats_json(flight)
        }

        {response, %{ctx | flight_id: flight_id}}

      :error ->
        {error(:flight_not_found), ctx}
    end
  end

  def handle(%{"type" => "reserve_seat"} = msg, ctx) do
    response =
      require_user(ctx, fn ->
        flight_id = msg["flight_id"] || ctx.flight_id

        with_flight(ctx, flight_id, fn pid ->
          case FlightServer.reserve_seat(pid, msg["seat_id"], ctx.user_id) do
            {:ok, reservation} ->
              %{
                type: "reservation_started",
                reservation_id: reservation.id,
                flight_id: flight_id,
                seat_id: reservation.seat_id,
                expires_at: iso(reservation.expires_at)
              }

            {:error, reason} ->
              error(reason)
          end
        end)
      end)

    {response, ctx}
  end

  def handle(%{"type" => "pay", "reservation_id" => reservation_id}, ctx) do
    response =
      require_user(ctx, fn ->
        with_flight(ctx, flight_of(reservation_id), fn pid ->
          case FlightServer.pay(pid, reservation_id, ctx.user_id) do
            {:ok, :processing} -> %{type: "payment_started", reservation_id: reservation_id}
            {:error, reason} -> error(reason)
          end
        end)
      end)

    {response, ctx}
  end

  def handle(%{"type" => "cancel", "reservation_id" => reservation_id}, ctx) do
    response =
      require_user(ctx, fn ->
        with_flight(ctx, flight_of(reservation_id), fn pid ->
          case FlightServer.cancel(pid, reservation_id, ctx.user_id) do
            {:ok, reservation} ->
              %{
                type: "reservation_update",
                reservation_id: reservation.id,
                status: to_string(reservation.status)
              }

            {:error, reason} ->
              error(reason)
          end
        end)
      end)

    {response, ctx}
  end

  def handle(%{"type" => "my_reservations"}, ctx) do
    response =
      require_user(ctx, fn ->
        reservations =
          ctx.persistence
          |> Persistence.get_reservations()
          |> Enum.filter(&(&1.user_id == ctx.user_id))
          |> Enum.map(&reservation_json/1)

        %{type: "my_reservations", reservations: reservations}
      end)

    {response, ctx}
  end

  def handle(_message, ctx), do: {error(:invalid_message), ctx}

  # --- Auxiliares ---

  # Ejecuta `fun` solo si la conexión está registrada; si no, error :not_registered.
  defp require_user(%{user_id: nil}, _fun), do: error(:not_registered)
  defp require_user(_ctx, fun), do: fun.()

  # Resuelve el FlightServer del vuelo y ejecuta `fun.(pid)`; si no existe, :flight_not_found.
  defp with_flight(ctx, flight_id, fun) do
    case ctx.lookup.(flight_id) do
      {:ok, pid} -> fun.(pid)
      :error -> error(:flight_not_found)
    end
  end

  # El reservation_id tiene la forma "<flight_id>-r<n>": el prefijo es el vuelo.
  defp flight_of(reservation_id), do: reservation_id |> String.split("-r", parts: 2) |> hd()

  defp find_or_create_user(persistence, name) do
    case Enum.find(Persistence.get_users(persistence), &(&1.name == name)) do
      nil ->
        user = %User{id: "user_#{System.unique_integer([:positive])}", name: name}
        :ok = Persistence.put_user(user, persistence)
        user

      user ->
        user
    end
  end

  defp error(reason), do: %{type: "error", reason: to_string(reason)}

  defp flight_json(%Flight{} = flight, airline_names) do
    %{
      id: flight.id,
      airline: Map.get(airline_names, flight.airline_id, flight.airline_id),
      origin: flight.origin,
      destination: flight.destination,
      departs_at: iso(flight.departs_at),
      price: flight.price,
      seat_count: map_size(flight.seats)
    }
  end

  defp flight_summary(%Flight{} = flight) do
    flight |> flight_json(Map.new(Seed.airlines())) |> Map.delete(:seat_count)
  end

  defp seats_json(%Flight{} = flight) do
    flight.seats
    |> Map.values()
    |> Enum.sort_by(&String.to_integer(&1.id))
    |> Enum.map(fn seat -> %{id: seat.id, status: to_string(seat.status)} end)
  end

  defp reservation_json(%Reservation{} = reservation) do
    %{
      id: reservation.id,
      flight_id: reservation.flight_id,
      seat_id: reservation.seat_id,
      status: to_string(reservation.status),
      created_at: iso(reservation.created_at),
      expires_at: iso(reservation.expires_at)
    }
  end

  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
