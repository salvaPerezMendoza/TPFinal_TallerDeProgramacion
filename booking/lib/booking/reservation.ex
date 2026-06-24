defmodule Booking.Reservation do
  @moduledoc """
  Reserva de un asiento por un usuario. Es solo una estructura de datos; las
  transiciones de estado las hace `Booking.Flight`.

  Una reserva nace `:pending` y termina en un único estado final:
  `:confirmed`, `:cancelled` o `:expired`.
  """

  # Plazo por defecto de una reserva pendiente: 1 minuto (regla del enunciado), en
  # milisegundos para que coincida con el timer del FlightServer (Process.send_after).
  @default_ttl_ms 60_000

  @enforce_keys [:id, :flight_id, :seat_id, :user_id, :created_at, :expires_at]
  defstruct [
    :id,
    :flight_id,
    :seat_id,
    :user_id,
    :created_at,
    :expires_at,
    status: :pending
  ]

  @type status :: :pending | :confirmed | :cancelled | :expired

  @type t :: %__MODULE__{
          id: String.t(),
          flight_id: String.t(),
          seat_id: String.t(),
          user_id: String.t(),
          status: status(),
          created_at: DateTime.t(),
          expires_at: DateTime.t()
        }

  @doc """
  Crea una reserva `:pending` con `expires_at = now + ttl_ms`. Ese plazo es la única
  fuente de verdad del deadline: el mismo valor con el que el `FlightServer` programa el
  timer de expiración.

  `now` y `ttl_ms` se reciben por parámetro para que la creación sea determinista
  (testeable); disparar el timer real es responsabilidad del proceso (FlightServer).
  """
  @spec new(String.t(), String.t(), String.t(), String.t(), DateTime.t(), pos_integer()) :: t()
  def new(id, flight_id, seat_id, user_id, %DateTime{} = now, ttl_ms) do
    %__MODULE__{
      id: id,
      flight_id: flight_id,
      seat_id: seat_id,
      user_id: user_id,
      status: :pending,
      created_at: now,
      expires_at: DateTime.add(now, ttl_ms, :millisecond)
    }
  end

  @doc "Plazo por defecto (en milisegundos) de una reserva pendiente: 1 minuto."
  @spec default_ttl_ms() :: pos_integer()
  def default_ttl_ms, do: @default_ttl_ms
end
