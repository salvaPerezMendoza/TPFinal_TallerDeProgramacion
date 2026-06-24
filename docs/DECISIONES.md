# Decisiones de diseño

> Registro de las decisiones de arquitectura tomadas en la Etapa 1, con su **porqué** y
> **cómo se defienden** en el coloquio. Al final, los **defaults menores a confirmar con
> el grupo**. Sirve de guía para la defensa oral y para que el grupo ratifique o cambie.

## Decisiones tomadas (firmes)

### D1 — Pago simulado en el backend con `Task.Supervisor`
**Decisión:** el pago (demora aleatoria de 1-5 s) corre como una **tarea supervisada** del
lado del servidor. Flujo: el cliente manda `pay` → el `FlightServer` lanza, vía
`PaymentSupervisor` (`Task.Supervisor`), una tarea que espera 1-5 s y al terminar le manda
`confirm` al propio `FlightServer`. La confirmación se aplica **solo si la reserva sigue
`pending`**.

**Por qué:**
- El backend es la **única fuente de verdad**: la confirmación se decide en el servidor, no
  en el navegador.
- La demora **no debe correr dentro del `FlightServer`** (mientras duerme no atendería su
  mailbox y bloquearía el vuelo). Sacarla a una tarea mantiene al dueño del estado siempre
  receptivo (regla de la cátedra: "el dueño del estado decide rápido y delega el trabajo
  pesado").
- Cumple el requisito OTP del enunciado de tener **tareas auxiliares** separadas del dominio.
- Hace **natural** la carrera "pago vs. expiración" (edge case 8.2): el `confirm` que llega
  tarde se evalúa sobre el estado ya final y se ignora.

**Cómo se defiende:** "El pago es trabajo diferido; lo modelamos como una `Task` supervisada
para no bloquear el `FlightServer`. El resultado vuelve como un mensaje más, que el vuelo
serializa con las demás operaciones; por eso un pago tardío nunca pisa una expiración."

**Alternativa descartada:** simular la demora en el frontend. Más simple, pero deja la
lógica de pago como detalle de UI y aprovecha menos OTP.

### D2 — Reservas `pending` al reiniciar → se expiran al bootear
**Decisión:** al levantar el servidor, toda reserva que estaba `:pending` pasa a `:expired`
y libera su asiento. Las `:confirmed`, `:cancelled` y `:expired` se recargan tal cual.

**Por qué:**
- El timer de expiración (`Process.send_after`) **se pierde** al reiniciar (es estado en
  memoria, no persistido). Mantener una reserva "pendiente" sin un timer que la limpie
  podría dejar un asiento **retenido para siempre**.
- Un reinicio del servidor es un evento **anormal**; lo correcto es no retener asientos de
  un proceso de pago que quedó interrumpido. Liberar el asiento mantiene las invariantes
  simples y predecibles.

**Cómo se defiende:** "Persistimos todas las reservas con su estado. Las finales se
recargan idénticas. Las pendientes no pueden sobrevivir tal cual porque su timer vivía en
memoria; en vez de inventar un timer nuevo, las cerramos como `expired` y liberamos el
asiento. Es la opción más conservadora y mantiene la invariante de estado final único."

**Alternativas descartadas:** restaurarlas `pending` con un timer nuevo (regala tiempo); o
recalcular el restante según `expires_at` (más lógica de bordes para poca ganancia).

### D3 — WebSocket con `cowboy` puro + `jason`
**Decisión:** usar la dependencia **`cowboy`** directamente, con un handler
`:cowboy_websocket`, y **`jason`** para (de)serializar JSON. Son las **únicas** dependencias
extra del backend.

**Por qué:**
- El TP es esencialmente WebSocket; `cowboy` puro nos da exactamente eso con **mínima
  superficie** y control total, sin capas intermedias que explicar.
- `jason` es la librería JSON estándar del ecosistema; es necesaria sí o sí para hablar con
  el navegador.
- Mantener **pocas dependencias** facilita la defensa oral (entendemos todo lo que corre).

**Cómo se defiende:** "Elegimos `cowboy` puro en vez de `plug_cowboy` porque solo
necesitamos un endpoint WebSocket; no queríamos sumar `Plug` como capa extra. `jason` es la
librería JSON de facto. Nada más."

**Alternativa descartada:** `plug_cowboy` (cómodo si hubiera muchos endpoints HTTP, pero
agrega `Plug` para defender).

### D4 — Supervisor raíz con estrategia `:rest_for_one`
**Decisión:** el supervisor raíz usa `:rest_for_one` con los hijos ordenados por
dependencia: `Persistence` → `Registry` → `UserServer` → `Catalog` → `FlightSupervisor` →
`PaymentSupervisor` → `WebEndpoint`.

**Por qué:**
- Hay una **cadena de dependencias**: los `FlightServer` se registran en `Registry` y
  cargan de `Persistence`. Si `Registry` cae, los `FlightServer` quedan "vivos pero no
  encontrables". Con `:rest_for_one`, al reiniciar `Registry` se reinician también los que
  arrancaron **después** (incluido `FlightSupervisor`), que se re-registran y recargan
  desde DETS → todo vuelve consistente.
- `WebEndpoint` arranca último: solo aceptamos conexiones con el dominio ya listo.

**Cómo se defiende:** "Ordenamos los hijos por dependencia y usamos `:rest_for_one` para que
una caída en una pieza base reinicie a los que dependen de ella, sin tocar a los anteriores.
Así nunca quedan procesos colgados de un `Registry` que ya no existe."

**Alternativa descartada:** `:one_for_one` (más simple, pero dejaría los `FlightServer`
inconsistentes ante una caída de `Registry`/`Persistence`).

### D5 — Ids de reserva generados por el `FlightServer` (contador legible)
**Decisión:** el `FlightServer` (la cáscara con efectos sobre `Booking.Flight`) genera los
ids de reserva con un **contador por vuelo**: `"<flight_id>-r<n>"` (ej. `"AR1001-r1"`).
Son únicos entre vuelos porque el `flight_id` lo es, y legibles para la demo y el coloquio.

**Por qué:** generar un id es un efecto (no determinista) → vive en el proceso, no en el
dominio puro. Un contador en el estado del GenServer es simple y se serializa solo (el
proceso atiende los pedidos de a uno).

**Deuda a saldar en la etapa de persistencia:** el contador (`seq`) vive en memoria. Al
reiniciar el servidor y recargar las reservas desde DETS hay que **restaurar
`seq = max(n existente) + 1`** (el mayor sufijo numérico entre las reservas ya
persistidas, más uno) para que los ids nuevos **no colisionen** con los ya emitidos.
Mientras no haya persistencia, `seq` arranca en 1.

**Alternativa:** id aleatorio (`System.unique_integer`) — sin esa deuda, pero menos legible.

---

## Defaults menores — **A CONFIRMAR CON EL GRUPO**

> No bloquean la arquitectura; son elecciones razonables que tomé para avanzar, pero el
> grupo debería ratificarlas o cambiarlas.

### C1 — Namespace OTP `Booking`
Todos los módulos cuelgan de `Booking.*` (`Booking.FlightServer`, etc.). Es solo un nombre;
si el grupo prefiere otro (`Flights`, `Reservas`, el nombre del proyecto del grupo, etc.),
es un cambio mecánico. **A confirmar.**

### C2 — Usuario solo por nombre, sin password
El `register` toma solo un `name` y devuelve un `user_id`. No hay autenticación real
(login/clave). Para un TP centrado en concurrencia y tiempo real alcanza, pero **a
confirmar** si el grupo quiere algo más (p. ej. email, o evitar nombres duplicados).

### C3 — Estado de los asientos **derivado** de las reservas (sin tabla `seats`)
No persistimos una tabla de asientos aparte. El estado de cada asiento se **reconstruye**
al bootear a partir de las reservas del vuelo: una reserva `:confirmed` ⇒ asiento ocupado;
sin reserva activa ⇒ asiento libre.

**El enunciado pide "persistir el estado actual de los asientos". ¿Por qué el estado
derivado igual lo cumple?**
- El requisito real es de **comportamiento**: tras apagar y levantar, el estado de los
  asientos debe quedar correcto. Eso se cumple: reconstruimos los asientos desde las
  reservas persistidas y quedan exactamente como correspondía.
- Las reservas (que **sí** persistimos) **determinan unívocamente** el estado de los
  asientos. Guardar los asientos por separado sería **información redundante** y abre la
  puerta a que asientos y reservas se contradigan (dos fuentes de verdad). Derivar mantiene
  **una sola fuente de verdad**, que es más correcto y más fácil de defender.
- Combina con [D2](#d2--reservas-pending-al-reiniciar--se-expiran-al-bootear): como las
  `pending` se expiran al bootear, al reconstruir solo las `:confirmed` ocupan asiento.

**A confirmar:** si en el coloquio se prefiere mostrar una tabla `seats` explícita, es un
cambio acotado (agregar la tabla y escribir el estado del asiento en cada transición). Lo
dejamos anotado como opción.
