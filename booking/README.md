# Booking — backend (Elixir/OTP)

Backend del sistema de reserva de asientos en vuelos. Cliente-servidor en tiempo real
sobre WebSocket. La arquitectura, el modelo de datos, el protocolo y las decisiones de
diseño están documentados en [`../docs/`](../docs).

> Para la visión completa del TP (integrantes, cómo levantar back + front, guion de demo,
> arquitectura y limitaciones), ver el [README raíz](../README.md).

## Requisitos

- Elixir `~> 1.19` sobre Erlang/OTP 28.

## Puesta en marcha

```sh
mix deps.get      # trae las dependencias (cowboy, jason)
mix test          # corre los tests
iex -S mix        # levanta la aplicación en una consola interactiva
```

## Probar el WebSocket (wscat)

Con la app levantada (`iex -S mix`; el listener queda en `ws://localhost:4000/ws`), desde
otra terminal:

```sh
npx wscat -c ws://localhost:4000/ws
```

Ya conectado, escribí el mensaje y Enter (en modo interactivo no hay líos de comillas):

```json
{"type":"list_flights"}
```

Devuelve `{"type":"flights","flights":[...]}` con los vuelos sembrados. El protocolo completo
está en [`../docs/protocolo.md`](../docs/protocolo.md).

## Demo: forzar un rechazo de pago

El pago simulado tiene una tasa de éxito configurable (`:payment_success_rate`, por defecto
`1.0` = siempre confirma, para que la demo no dependa del azar). Para mostrar el camino de
**pago rechazado**, bajá el knob en una consola `iex -S mix`:

```elixir
Application.put_env(:booking, :payment_success_rate, 0.0)   # 0.0 = siempre rechaza
# ... hacé un pago en la UI: la reserva sigue pendiente hasta que vence ...
Application.put_env(:booking, :payment_success_rate, 1.0)   # volver a "siempre confirma"
```

(También puede fijarse en `config/config.exs`.)

## Verificación antes de commitear

```sh
mix check         # = mix format --check-formatted + mix compile --warnings-as-errors
```

### Hook de git (una vez por clon)

El repositorio incluye un hook de pre-commit en `../.githooks/` que corre `mix check`
antes de cada commit. Para activarlo en tu clon, una sola vez:

```sh
git config core.hooksPath .githooks
```

(Se configura desde la raíz del repositorio, no desde `booking/`.)

## Dependencias

Solo dos, ambas de runtime:

- **cowboy** — servidor HTTP/WebSocket.
- **jason** — (de)serialización JSON del protocolo.
