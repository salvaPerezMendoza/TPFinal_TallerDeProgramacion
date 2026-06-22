defmodule Booking.MixProject do
  use Mix.Project

  def project do
    [
      app: :booking,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Booking.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:usage_rules, "~> 0.1", only: [:dev]},
      # Servidor HTTP/WebSocket: comunicación en tiempo real con el frontend.
      {:cowboy, "~> 2.16"},
      # (De)serialización JSON del protocolo WebSocket.
      {:jason, "~> 1.4"},
      {:claude, "~> 0.5", only: [:dev], runtime: false},
      # Requerido por :claude para sus mix tasks (generación/patching de proyecto).
      {:igniter, "~> 0.8.1", only: :dev}
    ]
  end
end
