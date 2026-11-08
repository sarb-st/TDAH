# AppTDAH — Definición del proyecto

Este archivo es la fuente de verdad del proyecto. Describe qué es la app, cómo funciona cada parte y cómo se construye. Leelo completo antes de cualquier tarea. Si una instrucción nueva contradice algo de acá, preguntá antes de seguir.

---

## 0. Sobre el usuario y cómo trabajar con él

- El usuario es diseñador industrial, **no programador**. No lee código.
- La app está pensada para personas con TDAH.
- Los datos personales (nombres, ciudad, etc.) están en `CLAUDE.local.md`, que existe solo en la PC del usuario y no se sube. Leelo si existe; nunca copies su contenido al repositorio.
- **No tiene Mac.** Trabaja con una compu Windows y un iPhone.
- Explicale siempre en **español**, en pocas líneas, qué hiciste y qué tiene que hacer él (si tiene que hacer algo). Los términos técnicos pueden ir en inglés.
- Cuando haya que elegir algo que cambia lo que él va a ver o usar, preguntale. Lo puramente técnico, decidilo vos y contale en una línea.

---

## 1. Visión

Una app iOS nativa que convierte lo que el usuario dicta en citas, tareas, proyectos e ideas, y **lo empuja a empezar**. El problema central no es organizar: es la **iniciación**.

**El problema.** No siente urgencia, no hay consecuencias inmediatas, evita, y sin un momento definido el arranque queda siempre en el aire. Es un solo patrón: falta un momento de arranque comprometido y con presión real.

**El diferenciador.** Combinar en un solo flujo captura por voz, clasificación con IA, desglose y enrutado al calendario, y además atacar el paso de "tengo la lista" a "estoy haciendo el paso 1".

**Principios de diseño (aplican a todo):**

1. **Captura sin fricción.** La captura nunca se bloquea ni se pierde.
2. **Nada queda en el aire.** Toda acción tiene una hora de arranque.
3. **Una sola cosa a la vista.** La pantalla principal muestra solo lo próximo.
4. **Sin culpa acumulada.** Nada de listas rojas ni pilas de pendientes vencidos.
5. **La IA propone, el usuario decide.** Siempre se puede editar lo que propone la IA.

---

## 2. Mecanismo de arranque (el corazón de la app)

Cada acción es una cita con **hora de arranque**, no con fecha de entrega. A esa hora, la app fuerza una decisión.

### 2.1 Hora de arranque y duración
- Toda tarea tiene **hora de arranque** y **duración** del slot ("hoy 18:00, 45 min").
- No se usan deadlines como motor de arranque (los proyectos sí tienen deadline, ver 5.2).

### 2.2 Countdown
- Antes del slot, una cuenta regresiva visible en la pantalla principal y en el widget ("comienza en 4:32").

### 2.3 "Empiezo" o "Ahora no"
A la hora del slot, la app pide una decisión binaria. **No existe snooze ni recordatorio que se silencia.** La decisión se toma con un gesto consciente sobre el círculo (ver `diseno/DISENO.md`), no con un toque reflejo.
- **Empiezo** (apretar el círculo y deslizar hacia arriba) → empieza el timer del slot.
- **Ahora no** (apretar el círculo y mantenerlo quieto 1,5 s) → acto explícito y registrado: el slot queda cerrado y la app pregunta **"¿Cuándo, entonces?"**. Nada queda en el aire:
  - Propone **3 slots concretos** que respetan el calendario del usuario y el **horario del lugar** (ver 5.1), cada uno con un renglón que explica por qué.
  - **Otra hora**: días y horarios libres para elegir a mano.
  - **Ya no la voy a hacer**: archiva la tarea a propósito (se puede recuperar).
  - La pantalla es liviana: quien pospone suele estar cansado o abrumado.
- **Notificación**: a la hora llega una notificación común. Si se descarta sin decidir, vuelve a los **3 minutos**; al **tercer descarte** el slot se cierra como "Ahora no" y, al abrir la app, lo primero es "¿Cuándo, entonces?". Los tres avisos se programan de antemano y se cancelan apenas el usuario decide (iOS no permite impedir que se descarte una notificación).

### 2.4 Fin del slot
Cinco minutos antes del final llega un aviso suave. Cuando se cumple la duración, la app muestra primero una **recompensa** (animación y mensaje de ánimo que varía) y después pregunta "¿Cómo seguimos?":
1. **Terminé** → se cierra y se registra el tiempo real.
2. **Necesito más** → +10, +15 o +30 min. Se puede extender varias veces. Cada extensión suma al tiempo real.
   - Si la extensión choca con el próximo slot, avisa y ofrece correrlo: "Con +30 pisás 'preparar el menú semanal' de las 19:00. ¿Lo corro?".
3. **Paro por hoy** → pide **obligatoriamente** la próxima hora para retomar.

### 2.5 Sin respuesta
- Si el usuario no contesta al fin del slot, después de **15 min** la sesión queda **pausada** (ni terminada ni cerrada).
- Al abrir la app, esa pregunta pendiente aparece antes que cualquier otra cosa.

### 2.6 Sin culpa acumulada
- La app nunca genera culpa consigo misma.
- Un slot cerrado con "Ahora no" es un **dato neutro**: se muestra como "slot cerrado", nunca como "tarea fallida". Queda marcado en el día como rastro visible.
- Si el usuario vuelve después de días sin usar la app, lo recibe limpia con lo próximo, no con una pila de vencidos.
- La única culpa que entra es la social (aviso a otra persona), y solo si el usuario la activa en el dial.

---

## 3. Dial de intensidad y persona de accountability

### 3.1 Dial
Un ajuste que regula cuánto cuesta decir "Ahora no". Existe porque el cerebro se habitúa a cualquier consecuencia fija; cuando eso pasa, el usuario sube el dial.

| Nivel | Qué pasa con "Ahora no" |
| --- | --- |
| Bajo (por defecto) | El slot queda marcado como cerrado en el día. |
| Medio | Fricción: escribir por qué se pospone, o mantener apretado más tiempo. |
| Alto | Se avisa a la persona de accountability. |

### 3.2 Persona de accountability
- Una persona elegida por el usuario recibe avisos por un **bot de Telegram**.
- Avisos en **los dos sentidos**:
  - Cuando el usuario **arranca** un slot ("[nombre] arrancó su slot de las 18:00"). Es refuerzo positivo, para que la relación no sea solo de control.
  - Cuando dice **"Ahora no"** (solo en nivel alto).
  - En proyectos: después de X replanteos seguidos y cuando se cumple un hito a tiempo (ver 5.2).
- El usuario elige qué se comparte. Arranca **apagado**; se activa al subir el dial.

---

## 4. Captura y clasificación

- El usuario dicta (o escribe) y la IA clasifica en **cinco categorías**: CITA, TAREA, PROYECTO, IDEA, INBOX.
- **La captura se guarda siempre al instante**, aunque falten datos.
- **Varias cosas en un dictado** → la IA las separa en capturas distintas ("llamar al banco, idea para el portfolio y el jueves dentista" = tres).
- **Si la IA duda** → muestra sus dos mejores opciones ("¿tarea o idea?") y el usuario elige con un toque. Si no contesta, va al INBOX.
- **Convertir** → botón para pasar una tarea a proyecto y viceversa, sin volver a cargar nada.
- **La IA nunca inventa contenido** que el usuario no dijo.

### Pantalla principal: "la una cosa"
- Muestra solo lo próximo (slot o cita), con su countdown y descripción.
- Deslizando hacia el costado se ven los **dos siguientes**; a los pocos segundos vuelve sola a lo próximo.
- Lo pendiente de resolver **ocupa esta pantalla hasta resolverlo**: una tarea sin hora, una sesión pausada sin respuesta.

---

## 5. Las cinco categorías

### 5.1 TAREA
Cosas de corto plazo, que se terminan en el día o en una o dos sesiones. Ejemplos: devolver un paquete, cocinar, limpiar, hacer una llamada, preguntarle algo a alguien, definir el lugar de vacaciones, organizar el menú semanal, regar las plantas, hacer el surtido.

- **Hora obligatoria.**
  - El usuario la dice al dictar, o la app propone una y el usuario confirma.
  - Si no la dijo y rechaza la propuesta, la tarea queda en estado **"falta hora"** y bloquea la pantalla principal hasta que se le asigne una. La captura en sí nunca se bloquea.
- **Desglose.**
  - La IA decide sola si la tarea necesita desglose.
  - Botón para desglosar más, **por paso** (no toda la lista), hasta **3 niveles** de profundidad. El tope evita que desglosar se vuelva una forma de no arrancar.
- **Horario del lugar.** Si la tarea depende de que algo esté abierto (llamar al banco, ir a una oficina), la IA estima el horario de atención, el usuario lo confirma o corrige una vez, y la app lo recuerda. Las horas propuestas siempre lo respetan.
- **Slot.** Cubre la tarea entera, con duración. Adentro el usuario va tachando pasos en una ruleta.
- **Cierre.** Terminé / necesito más / paro por hoy (con nueva hora obligatoria). Ver 2.4.
- **Recurrencia.** Para tareas que se repiten (regar plantas, surtido semanal).

### 5.2 PROYECTO
Algo con etapas, deadline final y puntos de control, que dura días o semanas. Ejemplos: organizar un cumpleaños, un proyecto de diseño, una mudanza, un viaje.

**Un proyecto es un contenedor de tareas.** Cada tarea de un proyecto funciona exactamente igual que una TAREA (hora, countdown, "Empiezo" o "Ahora no"). El proyecto solo agrega deadline, etapas, hitos y la vista del conjunto.

- **Plan.** La IA propone las etapas con **fechas repartidas hacia atrás desde el deadline**. El usuario edita.
- **Desglose por etapa.** Las tareas de cada etapa se desglosan **recién cuando se llega a esa etapa**, para no mostrar la montaña completa.
- **Estimación de tiempo.**
  - Cada tarea trae una estimación de tiempo.
  - La app registra **estimado vs. real** de cada tarea (desde que arranca el slot hasta que se cierra).
  - Con ese historial calcula un **factor personal** por tipo de tarea ("tarda 1,6 veces lo estimado en diseño, 0,8 en trámites") y corrige las estimaciones nuevas.
  - Al estimar una tarea nueva, la IA recibe como referencia tareas parecidas anteriores con su tiempo real.
  - Al principio estima mal; mejora con el uso.
- **Puntos de control (hitos).**
  - Si el usuario va atrasado, la app propone un **replanteo**: nuevas fechas o recortes para llegar al deadline.
  - Después de **X replanteos seguidos** (por defecto 2, ajustable en el dial), el siguiente replanteo avisa a la persona de accountability.
  - Un hito cumplido a tiempo **resetea el contador** y también puede avisarle.
- **Vista.**
  - En la pantalla principal: solo la próxima tarea del proyecto, más una **barra de tiempo restante hasta el deadline**.
  - El plan completo vive en una vista aparte del proyecto.

### 5.3 IDEA
Un bolazo que el usuario quiere sacar de la cabeza, sin compromiso de hacer nada ahora.

- **Captura cruda.** Se guarda tal cual la dijo (texto y, opcionalmente, el audio). La IA solo agrega un **título corto** y un **tema** (por ejemplo: diseño, casa, deporte, viajes).
- **Revisión semanal con hora.** Las ideas aparecen una por una y el usuario decide: archivar, dejar para la próxima revisión, o desarrollar.
- **Desarrollar.** Recién ahí la IA la estructura (objetivo, próximas acciones, obstáculos previsibles) o la convierte en tarea o proyecto.

### 5.4 INBOX
La red de seguridad para lo que la IA no pudo clasificar: capturas apuradas, dictados cortados o mal transcritos, cosas que el usuario todavía no decidió. Ejemplos: "lo de Martín", "pintar el living", "sacar turno".

- Solo llega lo que el usuario no resolvió con el toque de duda en el momento de capturar (ver 4).
- **Repaso diario corto** (unos 2 min, al final del día).
- Lo que pasa **2 semanas sin procesar se archiva solo**. No se borra: se puede recuperar.

### 5.5 CITA
Día y hora fija, normalmente con otra persona o en un lugar. Ejemplos: dentista, reunión, turno en una oficina pública.

- Va al calendario. **No entra en el "Empiezo" o "Ahora no"**.
- **Aviso de salida** = tiempo de trayecto + **buffer de 10 min** (ajustable), con countdown hasta la hora de salida.
  - Medio de transporte por defecto: **transporte público**. Se puede cambiar por cita.
  - La ciudad del usuario se configura en Ajustes de la app (nunca en el código).
- **Preparación.** La IA detecta si la cita necesita algo antes (documentos, compras) y propone una **TAREA de preparación** con su propia hora. El usuario la acepta o no.

---

## 6. Widgets y rituales

### Widgets
- **Captura.** Botones para hablar o escribir. Un widget no puede grabar audio: el toque abre la app directo en el dictado.
- **Lo que viene.** La próxima cosa con su descripción y la cuenta regresiva. En proyectos, también la barra de tiempo hasta el deadline.

### Rituales con hora
| Ritual | Cuándo | Qué hace |
| --- | --- | --- |
| Resumen nocturno | Cada noche | Citas de mañana, hora de salida y tareas de preparación pendientes. |
| Repaso del INBOX | Final del día | Aclarar lo que no se clasificó. |
| Revisión de ideas | Semanal | Archivar, dejar o desarrollar cada idea. |

---

## 6b. Diseño visual

La estética **"Respiro"** está cerrada y documentada en [`diseno/DISENO.md`](diseno/DISENO.md), con una muestra interactiva en `diseno/configurador.html`. Resumen: crema y salvia de día, bosque de noche, cambio continuo según la hora; Fraunces + SF Pro; un círculo que respira como protagonista, siempre del mismo tamaño y en el mismo lugar. En Ajustes, la apariencia puede ser **Automática**, **Siempre día** o **Siempre noche**.

---

## 7. Arquitectura técnica

App iOS nativa en **SwiftUI**, iOS 17 en adelante. **Sin servidor y sin servicios pagos.** Lo único con costo es la API de IA (centavos por uso). La app es la fuente de verdad; el calendario es solo un espejo de salida.

| Pieza | Qué hace |
| --- | --- |
| **SwiftData** | Base de datos en el iPhone: las 5 categorías, estados (viva, arrancada, pausada, cerrada, terminada), tiempos estimados y reales, rastro de slots, configuración del dial. |
| **EventKit → Google Calendar** | Escribe citas y slots de tareas en el calendario de Google del usuario, a través de su cuenta de Google agregada en el iPhone. Solo lo que tiene hora: IDEA e INBOX nunca salen al calendario. No usar OAuth ni la API de Google. |
| **Notificaciones locales** | Countdown, aviso de la hora (repetido a los 3 y 6 min si se descarta), aviso 5 min antes del final, fin de slot, aviso de salida, resumen nocturno, aviso de vencimiento de firma. |
| **WidgetKit** | Los dos widgets. |
| **MapKit** | Tiempo de trayecto en transporte público para el aviso de salida. |
| **Bot de Telegram** | La app llama directamente a la Bot API de Telegram para avisar a la persona de accountability. |
| **API de IA** | Clasifica, separa capturas, desglosa, estima tiempos, propone planes de proyecto y estructura ideas. Proveedor por definir. |

### Claves y tokens
- La clave de la API de IA y el token del bot de Telegram se cargan en una **pantalla de Ajustes** de la app y se guardan **solo en el Keychain** del iPhone.
- **Nunca se escriben en el código ni en el repositorio** (es público).

---

## 8. Cómo se construye (sin Mac)

1. Claude Code escribe el código en este repositorio **público** de GitHub.
2. **GitHub Actions** compila la app en un runner macOS **estándar** (gratis en repos públicos; nunca usar runners "xlarge", que se cobran).
   - El proyecto se genera con **XcodeGen** (`project.yml`), no con un `.xcodeproj` hecho a mano.
   - Corre las pruebas en el simulador.
   - Compila para iPhone **sin firmar** y empaqueta un `.ipa`.
   - Publica el `.ipa` como asset de un **GitHub Release**, descargable desde Safari en el iPhone.
3. El usuario instala el `.ipa` con **SideStore** usando su Apple ID gratis.
4. SideStore renueva la firma cada 7 días, con una automatización diaria de Atajos.

Cada cambio tarda unos 10–15 minutos en llegar al iPhone: conviene **agrupar varios cambios por compilación**.

---

## 9. Reglas permanentes

Sin una Mac al lado no se ven los errores en el momento. Estas reglas lo compensan y aplican siempre:

1. **Ninguna clave, token ni dato personal en el código o el repositorio.**
2. **Pruebas automáticas** para la lógica (horarios, countdown, estados de slots, factor de estimación, contadores de replanteo), corriendo en cada compilación.
3. **Capturas del simulador** en cada compilación, guardadas como artefacto, para revisar la interfaz antes de instalar.
4. **Registro de errores propio** dentro de la app y una pantalla de **Diagnóstico** para copiar el registro y pegarlo en Claude Code.
5. **Aviso de vencimiento de firma.** La app lee la fecha de vencimiento de su propia firma (provisioning profile embebido) y manda una notificación **dos días antes**: "Renová la firma: abrí SideStore".
6. **Copia de seguridad automática** de los datos en iCloud Drive (o en Archivos), para no perder nada si hay que reinstalar.
7. Si un workflow falla, leer el registro, corregir y reintentar antes de dar la tarea por terminada.
8. Mantener el README en español y actualizado, escrito para alguien que no programa.

---

## 10. Pendientes

- [x] **Probar el camino de instalación**: funciona de punta a punta (repositorio → compilación en la nube → instalación con SideStore). Si SideStore da -80045 al iniciar sesión, los pasos están en el README.
- [x] **Orden de construcción** (cada fase se usa unos días y se ajusta antes de pasar a la siguiente):
  1. **Arranque sin IA**: base técnica (capturas del simulador, Diagnóstico, aviso de firma), tareas cargadas a mano, Espera, Decidir, ¿Cuándo?, En curso, Fin del slot, notificaciones y copia de seguridad.
  2. **Captura**: dictado, clasificación con IA, INBOX.
  3. **Calendario y citas**: espejo en Google Calendar, aviso de salida, resumen nocturno.
  4. **Widgets**.
  5. **Desglose y proyectos**: estimado vs. real, factor personal.
  6. **Ideas, dial y persona de accountability**.
- [x] **Estética**: cerrada, ver 6b.
- [ ] **Proveedor de IA**: Claude u OpenAI.
- [ ] **Nombre definitivo de la app** (provisorio: AppTDAH).

## 11. Fase futura (no construir todavía)

- **Presencia (body doubling):** alguien presente en el momento de arrancar, aunque sea asíncrono.
- **Countdown en la pantalla de bloqueo** como Live Activity.
