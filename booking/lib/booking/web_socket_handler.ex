defmodule Booking.WebSocketHandler do
  @moduledoc """
  Handler WebSocket de Cowboy (`:cowboy_websocket`): **el proceso de conexión**. Cowboy/Ranch
  crea uno por cada conexión y llama a estos callbacks por nombre.

  Es **solo cáscara**: decodifica el JSON entrante, delega en `Booking.Protocol.handle/2` (la
  lógica testeable, separada de Cowboy) y vuelve a codificar la respuesta. El estado
  por-conexión arranca mínimo (más adelante: usuario y suscripciones).
  """

  alias Booking.{Persistence, Protocol}

  # Request HTTP entrante: le pedimos a Cowboy hacer el upgrade a WebSocket.
  def init(req, _opts) do
    {:cowboy_websocket, req, %{}}
  end

  # Tras el handshake: setup por-conexión (por ahora, nada).
  def websocket_init(state) do
    {:ok, state}
  end

  # Frame de texto del cliente: parsear -> despachar -> responder.
  def websocket_handle({:text, text}, state) do
    response =
      case Jason.decode(text) do
        {:ok, message} -> Protocol.handle(message, Persistence.get_flights())
        {:error, _reason} -> %{type: "error", reason: "invalid_message"}
      end

    {:reply, {:text, Jason.encode!(response)}, state}
  end

  # Otros frames (binario/ping/pong): los ignoramos por ahora.
  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  # Mensajes Erlang al proceso (ej. futuros broadcasts de un FlightServer): nada por ahora.
  def websocket_info(_info, state) do
    {:ok, state}
  end

  # La conexión se cerró: limpieza (más adelante: desuscribir).
  def terminate(_reason, _req, _state) do
    :ok
  end
end
