defmodule Booking.WebSocketHandler do
  @moduledoc """
  Handler WebSocket de Cowboy (`:cowboy_websocket`): **el proceso de conexión**. Cowboy/Ranch
  crea uno por cada conexión y llama a estos callbacks por nombre.

  Es **solo cáscara**: decodifica el JSON entrante, delega en `Booking.Protocol.handle/2` (la
  lógica testeable) y vuelve a codificar la respuesta. Su estado **es el contexto** de la
  conexión (`user_id`, `flight_id` + dependencias `persistence`/`lookup`), que `Protocol`
  actualiza en cada mensaje. (El broadcast a suscriptores es un sub-paso aparte.)
  """

  alias Booking.{FlightSupervisor, Persistence, Protocol}

  # Request HTTP entrante: le pedimos a Cowboy hacer el upgrade a WebSocket.
  def init(req, _opts) do
    {:cowboy_websocket, req, nil}
  end

  # Tras el handshake: armamos el contexto con los módulos reales del dominio.
  def websocket_init(_state) do
    context = %{
      user_id: nil,
      flight_id: nil,
      persistence: Persistence,
      lookup: &FlightSupervisor.lookup/1
    }

    {:ok, context}
  end

  # Frame de texto del cliente: parsear -> despachar -> responder (espejando `ref`).
  def websocket_handle({:text, text}, context) do
    {response, context} =
      case Jason.decode(text) do
        {:ok, message} ->
          {response, context} = Protocol.handle(message, context)
          {put_ref(response, message), context}

        {:error, _reason} ->
          {%{type: "error", reason: "invalid_message"}, context}
      end

    {:reply, {:text, Jason.encode!(response)}, context}
  end

  # Otros frames (binario/ping/pong): los ignoramos por ahora.
  def websocket_handle(_frame, context) do
    {:ok, context}
  end

  # Mensajes Erlang al proceso (ej. futuros broadcasts de un FlightServer): nada por ahora.
  def websocket_info(_info, context) do
    {:ok, context}
  end

  # La conexión se cerró: limpieza (más adelante: desuscribir).
  def terminate(_reason, _req, _context) do
    :ok
  end

  # Si el pedido traía `ref`, lo espejamos en la respuesta (correlación pedido/respuesta).
  defp put_ref(response, %{"ref" => ref}), do: Map.put(response, :ref, ref)
  defp put_ref(response, _message), do: response
end
