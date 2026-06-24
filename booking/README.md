# Booking — backend (Elixir/OTP)

Backend del sistema de reserva de asientos en vuelos. Cliente-servidor en tiempo real
sobre WebSocket. La arquitectura, el modelo de datos, el protocolo y las decisiones de
diseño están documentados en [`../docs/`](../docs).

## Requisitos

- Elixir `~> 1.19` sobre Erlang/OTP 28.

## Puesta en marcha

```sh
mix deps.get      # trae las dependencias (cowboy, jason)
mix test          # corre los tests
iex -S mix        # levanta la aplicación en una consola interactiva
```

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
