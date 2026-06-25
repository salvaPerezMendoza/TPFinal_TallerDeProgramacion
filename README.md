# Sistema de reserva de asientos en vuelos

TP Final — **Taller de Programación I** (FIUBA, cátedra Camejo). Aplicación cliente-servidor de
**reserva de asientos de vuelos en Argentina, en tiempo real**, con foco en concurrencia: varios
usuarios pueden mirar el mismo vuelo y competir por el mismo asiento, y el estado se mantiene
consistente en todos los clientes.

- **Backend:** Elixir + OTP (GenServer, Supervisor, DynamicSupervisor, Registry, Task.Supervisor)
  + **Cowboy** (WebSocket) + **DETS** (persistencia).
- **Frontend:** React + Vite (JavaScript) + WebSocket nativo + CSS simple.

## Integrantes

| Integrante | Padrón |
|---|---|
| Salvador Pérez Mendoza | 110189 |
| Juliana Ávila | 112027 |
| Nicolás Guziuk | 111587 |
| Mateo Gorga | 107730 |

## Stack

- **Backend:** Elixir `~> 1.19` / Erlang OTP 28. Dependencias de runtime: `cowboy` (HTTP/WebSocket)
  y `jason` (JSON). Persistencia en **DETS** (nativo de Erlang, sin dependencias).
- **Frontend:** React 19 + Vite. Sin librerías extra (WebSocket nativo, CSS propio).

## Estructura de carpetas

```
.
├── README.md                 ← este archivo
├── docs/                     ← documentación de diseño (fuente de verdad)
│   ├── enunciado.md          ← enunciado oficial
│   ├── arquitectura.md       ← árbol de supervisión + arquitectura de procesos
│   ├── modelo.md             ← entidades, estados e invariantes
│   ├── protocolo.md          ← protocolo WebSocket (mensajes + ejemplos JSON)
│   └── DECISIONES.md         ← decisiones técnicas con su porqué
├── booking/                  ← backend Elixir/OTP
│   ├── lib/booking/          ← dominio (Flight/Seat/Reservation), FlightServer, Persistence,
│   │                            Seed, Boot, WebEndpoint, WebSocketHandler, Protocol, …
│   ├── test/                 ← tests (dominio, concurrencia, persistencia, protocolo, broadcast)
│   └── config/config.exs     ← puerto WS, carpeta de datos, tasa de pago, seed
└── frontend/                 ← frontend React/Vite
    └── src/                  ← App, useBooking (hook WS), components/
```

## Requisitos

- **Elixir `~> 1.19`** sobre **Erlang/OTP 28**.
- **Node.js** (18+) y **npm** para el frontend.

## Cómo levantar

### Backend (puerto WebSocket 4000)

```sh
cd booking
mix deps.get          # trae cowboy y jason
iex -S mix            # levanta la app; el primer arranque siembra 60 vuelos en DETS
```

El listener WebSocket queda en `ws://localhost:4000/ws`.

### Frontend (puerto 5173)

```sh
cd frontend
npm install
npm run dev           # abre http://localhost:5173
```

> El frontend se conecta a `ws://localhost:4000/ws`; **levantá primero el backend**.

## Arquitectura (resumen)

Detalle completo en [docs/arquitectura.md](docs/arquitectura.md). El **corazón** del diseño: un
**`FlightServer` (GenServer) por vuelo** serializa todas las operaciones de ese vuelo, así dos
usuarios que pelean por el mismo asiento mandan mensajes al mismo proceso, que los atiende **de a
uno** → **un solo ganador, sin locks**.

Árbol de supervisión (`Booking.Application`, estrategia `:rest_for_one`):

```
Booking.Supervisor
├── Booking.Persistence                  (GenServer dueño de las tablas DETS)
├── {Registry, keys: :unique}            (índice {:flight, id} -> pid)
├── Booking.FlightSupervisor             (DynamicSupervisor: un FlightServer por vuelo)
│   └── Booking.FlightServer (xN)         (asientos + reservas + timers + suscriptores)
├── {Task.Supervisor} PaymentSupervisor  (pagos simulados 1-5 s)
└── Booking.WebEndpoint                  (Cowboy: 1 proceso por conexión WebSocket)
```

- **DynamicSupervisor + Registry:** un `FlightServer` por vuelo, creado bajo demanda y
  direccionable por id (no se vieron en clase; ver arquitectura.md).
- **Persistencia (DETS):** write-through sincrónico de cada reserva; al reiniciar, `Booking.Boot`
  reconstruye los vuelos desde disco (las confirmadas siguen ocupando; las pendientes vencidas se
  cierran; las vigentes re-arman su timer).
- **Tiempo real:** cada `FlightServer` guarda los pids suscriptos (con `Process.monitor`) y en cada
  cambio les empuja `seat_update`/`reservation_update`.
- **Pago simulado:** corre en una `Task` supervisada (no bloquea el vuelo); el `FlightServer`
  confirma solo si la reserva sigue pendiente (re-validación).

## Protocolo WebSocket (resumen)

Contrato completo en [docs/protocolo.md](docs/protocolo.md). Mensajes JSON con campo `type`.

- **Cliente → servidor:** `register`, `list_flights` (`date`/`destination`/`sort` opcionales),
  `open_flight`, `reserve_seat`, `pay`, `cancel`, `my_reservations`.
- **Servidor → cliente:** `registered`, `flights`, `flight_detail`, `reservation_started`,
  `reservation_update`, `seat_update` (broadcast), `my_reservations`, `payment_started`, `error`.

Probar a mano (con el backend levantado):

```sh
npx wscat -c ws://localhost:4000/ws
# luego, en modo interactivo:
{"type":"register","name":"Ana"}
{"type":"list_flights"}
```

## Guion de demo (en vivo)

1. **Backend:** `cd booking && iex -S mix` (siembra 60 vuelos la primera vez).
2. **Frontend:** `cd frontend && npm run dev`; abrir `http://localhost:5173`.
3. **Registrarse** con un nombre → entra a la app.
4. Ver el **listado de vuelos**.
5. **Filtrar por fecha**.
6. **Filtrar por destino**.
7. **Ordenar por precio** (asc/desc).
8. **Entrar al detalle** de un vuelo.
9. Ver la **grilla de asientos** con estados (disponible / reservado / confirmado).
10. **Elegir un asiento** y **Reservar** → queda **pendiente** con **contador de 1 minuto**.
11. **Pagar** → "procesando…" → **confirmado** (el asiento queda ocupado).
12. Abrir una **2ª pestaña** en el mismo vuelo → el asiento confirmado ya aparece (tiempo real).
13. En la 2ª pestaña, **reservar otro asiento** → la 1ª pestaña ve el cambio al instante
    (`seat_update`).
14. **Cancelar** una reserva pendiente → el asiento se **libera** y ambas pestañas lo reflejan.
15. **Dejar expirar** una reserva (no pagar en 1 min) → pasa a **expirada** y libera el asiento.
16. *(Opcional)* **Forzar un rechazo de pago**: en `iex`,
    `Application.put_env(:booking, :payment_success_rate, 0.0)`; el pago queda rechazado y la
    reserva sigue pendiente hasta vencer. Restaurar con `1.0`.
17. Ir a **Mis reservas** y ver los distintos estados (pendiente / confirmada / cancelada /
    expirada).
18. **Apagar el backend** (`Ctrl+C` dos veces en `iex`) y **volver a levantarlo** (`iex -S mix`).
19. **Re-abrir el vuelo**: el asiento confirmado **sigue ocupado** → persistencia y restore OK.

## Probar la persistencia

1. Reservá y **confirmá** un asiento (queda confirmado en disco, en `booking/data/`).
2. Cerrá el backend (`Ctrl+C` en `iex`) y volvé a levantarlo (`iex -S mix`).
3. Re-abrí el vuelo (o `my_reservations`): la reserva **sigue confirmada** y el asiento ocupado.

> El estado de los asientos se **deriva** de las reservas persistidas (una sola fuente de verdad);
> ver [docs/DECISIONES.md](docs/DECISIONES.md) C3 y D2.

## Reproducir los casos concurrentes

- **Dos usuarios, mismo asiento:** abrí dos pestañas en el mismo vuelo y reservá el **mismo
  asiento** casi a la vez → **solo una** lo consigue; la otra recibe "asiento tomado". El estado se
  sincroniza en ambas (`seat_update`).
- **Confirmar vs. expirar / cancelar vs. confirmar:** el `FlightServer` serializa todo y una reserva
  termina en **un único estado final** (un pago tardío no confirma una reserva ya expirada).
- **En `iex`** (el test de serialización está en el código):
  ```sh
  cd booking && mix test
  ```
  Incluye un test de **100 procesos** pidiendo el mismo asiento a la vez → gana exactamente uno.

## Decisiones técnicas y limitaciones

- **Decisiones técnicas** (con su porqué y cómo se defienden): [docs/DECISIONES.md](docs/DECISIONES.md).

### Limitaciones conocidas

- **Pago simulado:** la tasa de éxito es configurable (`:payment_success_rate`, por defecto `1.0` =
  siempre confirma, para que la demo no dependa del azar). El rechazo se fuerza bajando el knob.
- **`reservation_update`** se emite a todos los suscriptos del vuelo y **el cliente filtra** por sus
  propios `reservation_id` (no se trackea el usuario en la suscripción). Ver D9.
- **Búsqueda/orden:** el backend soporta `date`/`destination`/`sort`, pero el frontend filtra
  **client-side** (más fluido). Ver D8.
- **Identidad:** registro simple **por nombre, sin contraseña**; re-registrarse con el mismo nombre
  reusa el `user_id`. No hay autenticación real.
- **Reconexión:** al reconectar, `my_reservations` refleja el estado real; no hay recuperación de
  contexto más allá de eso.
- Falta un test end-to-end directo de `Booking.Boot.run` (hoy cubierto por las piezas testeadas + un
  smoke manual).
