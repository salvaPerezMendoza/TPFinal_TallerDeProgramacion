# CLAUDE.md — TP Final Taller de Programación I (FIUBA)

> Copiá este archivo a la **raíz del repo del TP**. Claude Code lo lee automáticamente en cada
> sesión, así no tenés que repetir el contexto. Mantenelo corto y de alta señal: si crece demasiado,
> Claude empieza a ignorar partes.

## Qué es este proyecto
Sistema cliente-servidor de **reserva de asientos en vuelos** en tiempo real (vuelos dentro de Argentina).

- **Backend:** Elixir + OTP (GenServer, Supervisor, DynamicSupervisor, Registry) + **Cowboy** (WebSocket) + **DETS** (persistencia).
- **Frontend:** React + Vite + WebSocket nativo del navegador + CSS simple. **JavaScript** (no TypeScript) salvo que se justifique lo contrario.
- **Contexto:** TP universitario **grupal con defensa oral (coloquio)**. La prioridad #1 es que el código sea **simple, entendible y defendible oralmente**, no que sea impresionante.

## Documentos fuente (leerlos antes de decidir)
- `docs/enunciado.md` — enunciado oficial. **Fuente de verdad #1.** No saltear ningún requisito obligatorio.
- `docs/resumen-catedra.md` — conceptos vistos en clase. Guía de estilo y arquitectura esperada.

Orden de prioridad para tomar decisiones: (1) enunciado, (2) notas de la cátedra, (3) resumen de la materia, (4) buenas prácticas y criterio técnico.

> Nota importante: el resumen de la cátedra cubre GenServer, Supervisor y Application, pero
> **DynamicSupervisor, Registry, Task.Supervisor, Cowboy y DETS quedan fuera de lo visto en clase.**
> Cuando uses esas piezas, explicá el concepto con más detalle (las vamos a tener que defender).

## Reglas de oro (no negociables)
1. **No escribas código a ciegas.** Antes de implementar algo nuevo, proponé un plan y esperá mi OK. Usá plan mode.
2. **Preguntá antes de decisiones importantes** (arquitectura, modelo de datos, protocolo WebSocket, persistencia, concurrencia, timers, flujo de pago). Dame 2-3 opciones concretas con una recomendación. No inventes requisitos que no estén en el enunciado.
3. **Simplicidad > sofisticación.** Cero sobreingeniería. Si una solución es difícil de explicar en un coloquio, probablemente está mal para este TP.
4. **No agregues dependencias** sin justificarlas y preguntarme primero.
5. **El backend es la única fuente de verdad.** El frontend nunca decide el estado. Validar siempre el estado real antes de aceptar una operación.
6. **Concurrencia por diseño, no por suerte.** Las operaciones críticas de un vuelo se serializan en su `FlightServer` (GenServer). Pensar siempre el caso de dos usuarios compitiendo por el mismo asiento, no solo el caso feliz.
7. **No borres ni reemplaces código que ya funciona** sin explicarme por qué.
8. Al terminar una tarea, decime **qué quedó funcionando y qué falta**.

## Invariantes del dominio (deben cumplirse SIEMPRE)
- Un asiento no puede estar asignado a dos usuarios a la vez.
- Reserva confirmada → asiento ocupado de forma definitiva. Reserva cancelada o expirada → asiento liberado.
- Una reserva termina en **un único estado final**: `pending` → `confirmed` | `cancelled` | `expired`.
- No se puede confirmar una reserva ya expirada o cancelada. Un pago que llega tarde **no** confirma.
- Si dos usuarios reservan el mismo asiento a la vez, **solo uno** lo consigue.
- Tras apagar y reiniciar el servidor, no se pierden usuarios, vuelos ni reservas persistidas.

## Convenciones de código
- Módulos chicos, una responsabilidad cada uno. Separar **conexión / dominio / auxiliares**.
- Identificadores en inglés (`FlightServer`, `ReservationManager`, `reserve_seat`); comentarios y documentación en español.
- Las funciones que pueden fallar devuelven `{:ok, _}` / `{:error, reason}`.
- Comentar solo decisiones no obvias (el *por qué*), no el *qué*.
- Código Elixir formateado (`mix format`) y que compila **sin warnings**.

## Cómo verificar (correr SIEMPRE antes de decir "listo")
- Backend: `mix test`, `mix compile --warnings-as-errors`, `mix format --check-formatted`.
- Probar a mano en `iex -S mix`: levantar procesos, crashearlos, ver al supervisor reiniciarlos.
- Concurrencia/persistencia: seguir el "Guion de demo" del README.

## Estado del proyecto
<!-- Mantené acá una línea por etapa: qué quedó funcionando y qué falta. Ejemplo:
- [x] Etapa 2: backend mínimo, FlightServer y listado de vuelos OK.
- [ ] Etapa 3: reservas y concurrencia — en progreso.
-->
