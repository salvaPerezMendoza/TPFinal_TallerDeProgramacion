defmodule Booking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Árbol de supervisión (vacío por ahora — todavía no arrancamos procesos de dominio).
    # El árbol consolidado y el orden por dependencia están en docs/arquitectura.md.
    children = []

    # :rest_for_one → si una pieza base cae, se reinician también las que dependen de ella
    # (ver docs/DECISIONES.md, D4). El orden de los hijos codificará esa dependencia.
    opts = [strategy: :rest_for_one, name: Booking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
