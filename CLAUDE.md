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
- **Empiezo** (el círculo sigue al dedo; deslizar hacia arriba mientras la pantalla se llena de verde) → empieza el timer del slot.
  - Mientras corre, la pantalla principal **sigue siendo Inicio** (se puede capturar). La tarea en curso es la primera tarjeta del fichero, en verde, con lo que queda; al tocarla se ven la cuenta y la ruleta de pasos. El halo de Inicio toma un verde suave.
- **Ahora no** (deslizar hacia abajo hasta el borde y sostener 2 s, mientras el halo se agranda) → acto explícito y registrado. Primero aparece "Está bien, lo movemos." (o otro texto con la misma calidez, que va rotando) solo y grande; después el slot queda cerrado y la app pregunta **"¿Cuándo, entonces?"**. Nada queda en el aire:
  - Propone **3 slots concretos** que respetan el calendario del usuario y el **horario del lugar** (ver 5.1), cada uno con un renglón que explica por qué.
  - **Otra hora**: días y horarios libres para elegir a mano.
  - **Ya no la voy a hacer**: archiva la tarea a propósito (se puede recuperar).
  - La pantalla es liviana: quien pospone suele estar cansado o abrumado.
- **Aviso con sonido**: el comienzo (y sus repeticiones) y el fin del slot llegan como **notificación con una campanita corta y suave** propia, que suena una sola vez (en Ajustes se puede elegir el sonido de iOS). Con el iPhone en silencio, vibra.
  - Se probó AlarmKit (pantalla de despertador que suena en silencio) y se descartó el 2026-11-16: la pantalla la dibuja iOS, no se puede rediseñar y repetía el sonido sin parar. El código queda apagado en `Alarmas.swift`.
- **Notificación**: a la hora llega una notificación común. Si se descarta sin decidir, vuelve a los **3 minutos**; al **tercer descarte** el slot se cierra como "Ahora no" y, al abrir la app, lo primero es "¿Cuándo, entonces?". Los tres avisos se programan de antemano y se cancelan apenas el usuario decide (iOS no permite impedir que se descarte una notificación).

### 2.4 Fin del slot
Cinco minutos antes del final llega un aviso suave. Cuando se cumple la duración, la app muestra primero una **recompensa** (animación y mensaje de ánimo que varía) y después pregunta "¿Cómo seguimos?":
1. **Terminé** → se cierra, se registra el tiempo real; primero la pantalla entera en verde con un mensaje que rota ("¡Bien ahí!", "¡Eso!", "¡Buena, crack!", "¡Vamos!", "¡Bien metida!") y después una **celebración** de unos segundos (halo verde grande, un brote que crece y los minutos de foco del día y totales). "Terminé" también está disponible durante el slot, para terminar antes.
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
- **Se dicta desde el círculo de la pantalla principal:** micrófono → oreja (escucha; el halo reacciona a la voz) → cerebro (ordena).
  Termina con "Listo" o solo, después de **3 segundos de silencio**. Después aparece la revisión. Manteniendo apretado el círculo se escribe.
- **Idiomas:** se dicta en español, pero el usuario mezcla palabras en alemán e inglés. El mismo audio se reconoce a la vez en
  español y en alemán; la IA toma el sentido del español y la escritura de calles, locales y términos alemanes del alemán.
  Después, los lugares y direcciones se buscan en Apple Maps (cerca del usuario) y se corrigen con el nombre real.
- **Escribir en vez de dictar:** "o escribilo" debajo de la pista de Inicio. Lo escrito se ordena igual que el dictado;
  ahí mismo está "Cargar a mano" (pregunta si es tarea, cita, proyecto o idea).
- **Notas:** la IA solo pone en notas lo que el usuario pidió recordar o llevar; lo que no entiende va al Inbox.
- **La interfaz nunca nombra a la IA** (Claude): los botones dicen cosas como "Armar las etapas" u "Ordenar". Solo Ajustes la nombra.
- **La captura se guarda siempre al instante**, aunque falten datos.
- **Varias cosas en un dictado** → la IA las separa en capturas distintas ("llamar al banco, idea para el portfolio y el jueves dentista" = tres).
- **Si la IA duda** → muestra sus dos mejores opciones ("¿tarea o idea?") y el usuario elige con un toque. Si no contesta, va al INBOX.
- **Convertir** → botón para pasar una tarea a proyecto y viceversa, sin volver a cargar nada.
- **La IA nunca inventa contenido** que el usuario no dijo.

### Pantalla principal: "la una cosa"
- En el centro, el círculo que respira es el **micrófono**.
- Abajo, un **fichero** con lo próximo (slot o cita) y su countdown; las dos siguientes asoman debajo. Un toque lo despliega y aparece **"Ver todo"** (abre el listado); a los pocos segundos vuelve solo.
- En la primera tarjeta se ven el **lugar** y las **notas** de la tarea (qué llevar, qué no olvidar).
- Arriba, accesos que se abren a propósito: **listado** y **calendario por día** a la izquierda; **cajón** (inbox e ideas) y **ajustes** a la derecha.
  - **Listado** con pestañas: Hoy (por defecto), Tareas, Citas y Proyectos. En Hoy: "Hecho hoy" arriba (plegable y más tenue), una línea "Ahora" adonde baja solo al abrir, lo que falta elegir hora y lo que viene. El "+" de Hoy pregunta qué cargar; en las otras pestañas carga esa categoría. Tocando una tarea se ve su detalle, se edita, se archiva o se borra.
  - **Calendario** con franjas horarias, colores por categoría y el rastro rayado de los slots cerrados.
- **Colores por categoría** (tarea, cita, proyecto, idea, inbox): ver `diseno/DISENO.md`.
- Al cargar o editar una tarea, la app avisa si se pisa con otra y ofrece el próximo hueco libre.
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
- **Lugar, dirección y notas.** Opcionales y distintos de los pasos. La dirección se abre en Mapas. Al escribir el lugar, Mapas **sugiere lugares y direcciones** (cerca de donde estás o de tu ciudad) y corrige errores de tipeo.
- **Slot.** Cubre la tarea entera, con duración. Adentro el usuario va tachando pasos en una ruleta.
- **Cierre.** Terminé / necesito más / paro por hoy (con nueva hora obligatoria). Ver 2.4.
- **Recurrencia.** Para tareas que se repiten (regar plantas, surtido semanal).

### 5.2 PROYECTO
Algo con etapas, **fecha de inicio**, deadline final y puntos de control, que dura días o semanas. Ejemplos: organizar un cumpleaños, un proyecto de diseño, una mudanza, un viaje.

**Un proyecto es un contenedor de tareas.** Cada tarea de un proyecto funciona exactamente igual que una TAREA (hora, countdown, "Empiezo" o "Ahora no"). El proyecto solo agrega deadline, etapas, hitos y la vista del conjunto.

- **Plan.** Al crear el proyecto se eligen la fecha de inicio y la final (dos campos que abren un calendario y muestran cuánto dura) y "Armar las etapas" las reparte entre las dos fechas. El usuario las renombra, reordena, agrega o quita.
  - Las etapas van una detrás de otra. Cada una se edita en su ficha: nombre y **duración en días u horas**; las siguientes se corren. Si el plan se pasa de la fecha final, la app ofrece correr la fecha final o achicar las etapas que siguen.
  - **Reordenar** con manijas siempre visibles: una sesión que se mueve toma el horario del lugar al que va; una etapa que se mueve mantiene su duración y las fechas se reparten de nuevo.
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
  - En el listado, **un proyecto es una sola tarjeta**: etapas completas ("1/4"), etapa actual, días que faltan, línea de tiempo (las divisiones son las etapas) y próxima sesión.
  - En la pantalla principal: solo la próxima sesión del proyecto, como una tarjeta más del fichero, con su barra.
  - **Archivar** saca el proyecto de la vista junto con sus sesiones pendientes (se recupera en Proyectos → "Mostrar archivados"). **Borrar** lo elimina de verdad.
  - Si se le cambia el nombre, la app pregunta si rearma las etapas (se reemplaza lo no empezado; lo terminado queda). Sin etapas, adentro aparece "Armar las etapas". Las sesiones sueltas se pasan a una etapa con una flecha.
  - El plan completo vive adentro del proyecto: etapas que se abren, solo la actual con sus sesiones.

### 5.3 IDEA
Un bolazo que el usuario quiere sacar de la cabeza, sin compromiso de hacer nada ahora.

- **Captura cruda.** Se guarda tal cual la dijo (texto y, opcionalmente, el audio). La IA solo agrega un **título corto** y un **tema** (por ejemplo: diseño, casa, deporte, viajes).
- **Revisión semanal con hora.** Las ideas aparecen una por una y el usuario decide: archivar, dejar para la próxima revisión, o desarrollar.
- **Desarrollar.** Recién ahí la IA la estructura (objetivo, próximas acciones, obstáculos previsibles) o la convierte en tarea o proyecto.

### 5.4 INBOX
La red de seguridad para lo que la IA no pudo clasificar: capturas apuradas, dictados cortados o mal transcritos, cosas que el usuario todavía no decidió. Ejemplos: "lo de Martín", "pintar el living", "sacar turno".

- Solo llega lo que el usuario no resolvió con el toque de duda en el momento de capturar (ver 4).
- Vive en el **cajón** junto con las ideas (una lista con dos secciones), fuera del listado.
- **Repaso diario corto** (unos 2 min, al final del día).
- Lo que pasa **2 semanas sin procesar se archiva solo**. No se borra: se puede recuperar.

### 5.5 CITA
Día y hora fija, normalmente con otra persona o en un lugar. Ejemplos: dentista, reunión, turno en una oficina pública.

- Va al calendario. **No entra en el "Empiezo" o "Ahora no"**. En el fichero, al tocarla se ve cuánto falta para salir, para que empiece o para que termine.
- **Aviso de salida** = tiempo de trayecto + **buffer de 10 min** (ajustable), con countdown hasta la hora de salida.
  - **Avisos del día**: con trayecto, 2 h, 30 min y 5 min antes de salir, y "Salí ahora". Sin dirección, 2 h, 1 h y 30 min antes, y a la hora.
  - El trayecto se calcula **desde donde estás** (permiso de ubicación "mientras se usa la app") y se recalcula cada vez que se abre la app, para las citas de las próximas 24 h. Sin permiso, desde la casa cargada en Ajustes.
  - Medio de transporte por defecto: **transporte público**. Se puede cambiar por cita.
  - La ciudad y la casa del usuario se configuran en Ajustes de la app (nunca en el código).
- **Preparación.** La IA detecta si la cita necesita algo antes (documentos, compras) y propone una **TAREA de preparación** con su propia hora. El usuario la acepta o no.

---

## 6. Widgets y rituales

### Widgets
- **Captura.** Botones para hablar o escribir. Un widget no puede grabar audio: el toque abre la app directo en el dictado.
  Chico (un toque → dictado), mediano ("Hablá" y "Escribí") y redondo en la pantalla de bloqueo.
  Si hay algo pendiente de decidir, en vez del dictado de Inicio se abre la captura aparte.
- **Lo que viene.** La próxima cosa con su descripción y la cuenta regresiva. En proyectos, también la barra de tiempo hasta el deadline.
  Chico, mediano (lugar, notas, barra del proyecto y lo que sigue) y en la pantalla de bloqueo. Lo en curso va primero ("quedan");
  en una cita cuenta hasta la salida, el comienzo y el fin. Más de 6 h se muestra como hora ("mañana 18:00").
- **Cómo se conectan.** La app deja lo próximo en un archivo de una carpeta compartida (App Group) cada vez que cambia algo;
  el widget lo lee y cambia solo en cada inicio, salida y fin. SideStore renombra la carpeta: el nombre real se lee del perfil
  de la firma. La compilación firma "ad hoc" la app y los widgets con sus permisos para que SideStore los registre.

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
| **AlarmKit** (iOS 26+) | Alarmas que suenan en silencio al comienzo y al fin de cada slot. Pide permiso al cargar la primera tarea. |
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
  4. **Widgets** (hechos el 2026-11-16).
  5. **Desglose y proyectos**: estimado vs. real, factor personal.
  6. **Ideas, dial y persona de accountability**.
- [x] **Estética**: cerrada, ver 6b.
- [ ] **Minutos de foco**: ya se suman y se muestran en la celebración y en Ajustes; falta definir para qué más se usan.
- [x] **Proveedor de IA**: Claude (Anthropic), modelo `claude-opus-5-5` con esfuerzo bajo y salida JSON con esquema. La clave se carga en Ajustes y vive en el Keychain.
- [x] **Fase 2 (captura)** en marcha junto con versiones básicas de **citas** (Fase 3) y **proyectos** (Fase 5), a pedido del usuario: dictado, clasificación, revisión antes de guardar, inbox, ideas, citas con salida y alarma, espejo en el calendario del iPhone, resumen nocturno, proyectos con etapas, barra y replanteo con IA.
- [x] **Maquetas A, B y C** (2026-11-15): inicio con micrófono en el círculo y fichero, decidir con llenado de pantalla, colores por categoría, listado con pestañas, cajón, calendario rayado y proyectos como tarjeta con fechas, etapas editables y reordenables. Ver `diseno/`.
- [ ] **Ubicación en segundo plano** (permiso "Siempre" con cambios significativos de ubicación) para recalcular la salida sin abrir la app. Por ahora se recalcula al abrirla.
- [x] **Alarma**: notificación con campanita en vez de la pantalla de despertador (2026-11-16).
- [ ] **Nombre definitivo de la app** (provisorio: AppTDAH).
- [ ] **Logo e ícono** para la pantalla de inicio del iPhone.
- [ ] **Pantalla de carga** con animación al abrir la app.
- [ ] **Revisar el micrófono**: el usuario lo nota "medio raro" (2026-11-15). Ver si el toque largo (abre escribir) o el corte por silencio confunden.
- [ ] **Para una tanda grande** (pedido del 2026-11-16):
  - **Trayecto en auto**: cuando hay lugar o dirección, poder elegir entre transporte público y auto particular.
  - **Bloquear el trayecto en el calendario**: en las citas, reservar el tiempo de viaje antes y después.
  - **Resumen de las 21 h como pantalla**: la notificación abre una pantalla con lo de mañana, no queda solo en el aviso.
  - **Que el aviso encienda la pantalla bloqueada**: avisos "urgentes" (time-sensitive) para que pasen los modos de concentración.
- [ ] **Al final, cuando todo funcione:** rediseñar las pantallas internas que hoy son formularios con estilo de Ajustes del iPhone (nueva tarea, editar, ajustes, etapa, etc.), algunas muy cargadas o sin diseño.

## 11. Fase futura (no construir todavía)

- **Presencia (body doubling):** alguien presente en el momento de arrancar, aunque sea asíncrono.
- **Countdown en la pantalla de bloqueo** como Live Activity.
