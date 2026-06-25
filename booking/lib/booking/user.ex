defmodule Booking.User do
  @moduledoc """
  Usuario registrado del sistema. Identidad simple por nombre, sin password (ver
  docs/modelo.md). El `id` lo genera el backend y es lo que ata las reservas a un usuario.
  """

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @type t :: %__MODULE__{id: String.t(), name: String.t()}
end
