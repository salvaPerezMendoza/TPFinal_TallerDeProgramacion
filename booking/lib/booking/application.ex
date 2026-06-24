defmodule Booking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Árbol de supervisión. El árbol consolidado está en docs/arquitectura.md.
    children = [
      # Registry: índice {:flight, id} -> pid del FlightServer. Arranca primero porque
      # los FlightServer se registran en él al nacer.
      {Registry, keys: :unique, name: Booking.Registry},
      # DynamicSupervisor: crea/supervisa un FlightServer por vuelo, bajo demanda.
      Booking.FlightSupervisor
    ]

    # :rest_for_one → si el Registry cae, se reinician también los que arrancaron después
    # (el FlightSupervisor y sus vuelos), que se re-registran. Ver docs/DECISIONES.md D4.
    opts = [strategy: :rest_for_one, name: Booking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
