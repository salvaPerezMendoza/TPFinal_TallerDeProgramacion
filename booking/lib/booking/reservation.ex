defmodule Booking.Reservation do
  @moduledoc """
  Reserva de un asiento por un usuario. Es solo una estructura de datos; las
  transiciones de estado las hace `Booking.Flight`.

  Una reserva nace `:pending` y termina en un único estado final:
  `:confirmed`, `:cancelled` o `:expired`.
  """

  # Tiempo de vida de una reserva pendiente: 1 minuto (regla del enunciado).
  @ttl_seconds 60

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
  Crea una reserva `:pending`. `expires_at` se calcula como `now + 1 minuto`.

  `now` se recibe por parámetro para que la creación sea determinista (testeable);
  el timer real de expiración es responsabilidad del proceso (FlightServer).
  """
  @spec new(String.t(), String.t(), String.t(), String.t(), DateTime.t()) :: t()
  def new(id, flight_id, seat_id, user_id, %DateTime{} = now) do
    %__MODULE__{
      id: id,
      flight_id: flight_id,
      seat_id: seat_id,
      user_id: user_id,
      status: :pending,
      created_at: now,
      expires_at: DateTime.add(now, @ttl_seconds, :second)
    }
  end

  @doc "Tiempo de vida (en segundos) de una reserva pendiente."
  @spec ttl_seconds() :: pos_integer()
  def ttl_seconds, do: @ttl_seconds
end
