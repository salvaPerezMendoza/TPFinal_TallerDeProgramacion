defmodule Booking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Árbol de supervisión. El árbol consolidado está en docs/arquitectura.md.
    children = [
      # Persistence: único dueño de las tablas DETS. Arranca primero: los FlightServer
      # escriben a través de él (write-through).
      Booking.Persistence,
      # Registry: índice {:flight, id} -> pid del FlightServer. Los FlightServer se
      # registran en él al nacer.
      {Registry, keys: :unique, name: Booking.Registry},
      # DynamicSupervisor: crea/supervisa un FlightServer por vuelo, bajo demanda.
      Booking.FlightSupervisor
    ]

    # :rest_for_one → si una pieza base (Persistence/Registry) cae, se reinician también
    # los que arrancaron después (el FlightSupervisor y sus vuelos). Ver docs/DECISIONES.md.
    opts = [strategy: :rest_for_one, name: Booking.Supervisor]

    with {:ok, _pid} = ok <- Supervisor.start_link(children, opts) do
      # Con el árbol ya levantado, reconstruir los vuelos persistidos desde DETS.
      Booking.Boot.restore()
      ok
    end
  end
end
