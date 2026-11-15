# Guía de diseño · "Respiro"

Estética cerrada el 2026-11-06. La muestra interactiva de referencia es [`configurador.html`](configurador.html)
(abrila en un navegador): todo lo que dice esta guía está implementado ahí y es la fuente para pasarlo a SwiftUI.
Las pantallas se ajustaron el 2026-11-15 con tres maquetas aprobadas: [`maqueta-a.html`](maqueta-a.html) (inicio y decidir),
[`maqueta-b.html`](maqueta-b.html) (colores, listado, calendario y cajón) y [`maqueta-c.html`](maqueta-c.html) (proyectos).

## Idea

Una superficie tranquila, de naturaleza y bosque, con un solo protagonista: **un círculo que respira**.
La energía aparece en un único momento: cuando empezás algo.

## Tipografía

- **Fraunces** (serif suave, licencia OFL, se incluye en la app) para títulos de tarea, números de la cuenta regresiva y preguntas.
  Peso 400 en títulos, 300 en números.
- **SF Pro** (la del sistema) para todo lo demás.
- Todo respeta el tamaño de texto que el usuario elige en el iPhone (Dynamic Type).

## Color

Paleta **Salvia y crema** de día y **Bosque** de noche. Nunca rojo: los avisos usan un ocre apagado.

| Token | Mañana | Tarde | Noche |
| --- | --- | --- | --- |
| Fondo | `#F1F1EA` | `#F2E9DB` | `#141A16` |
| Superficie | `#FBF8F1` | `#FBF8F1` | `#1D2520` |
| Texto | `#35302A` | `#35302A` | `#E6E9E1` |
| Texto secundario | `#7B746A` | `#7B746A` | `#99A49A` |
| Primario (verde) | `#4E6B55` | `#4E6B55` | `#8FB197` |
| Halo | `#A9C2A5` | `#C3B591` | `#4A6B55` |
| Energía | `#86B892` | `#BCA96C` | `#7FAE8B` |
| Líneas | `#DAD1C2` | `#DCCFBC` | `#2F3B33` |
| Aviso | `#B0812F` | `#B0812F` | `#B0812F` |

### Colores por categoría (paleta "Bosque")

| Categoría | Color |
| --- | --- |
| Tarea | `#7FA383` verde |
| Cita | `#C9A35E` ocre |
| Proyecto | `#8EA3B8` azul grisáceo |
| Idea | `#9C92B4` lila |
| Inbox | `#C2B49C` arena |

- **Tarjetas:** banda de color de 6 pt a la izquierda y el nombre de la categoría escrito en su color (texto, no etiqueta con fondo),
  más oscuro de día y más claro de noche para que se lea.
- **Calendario:** cada bloque con un fondo suave de su color y una rayita del color pleno; en la semana, puntitos de color por día.
  El slot cerrado con "Ahora no" se ve **rayado en diagonal**.
- **Blanco cálido** `#FBF8F1` para "Empiezo", "Ahora no" y "Está bien, lo movemos." sobre la pantalla llena de color.
- **Salvia apagada** `#B9C4B3` llena la pantalla al sostener "Ahora no" (de noche, una mezcla del halo con el fondo).

### Apariencia (pantalla de Ajustes)

- **Automático:** los colores cambian de a poco con la hora, sin saltos, mezclando entre estos puntos:
  5:00 noche → 5:48 crepúsculo → 6:36 alba → 8:00 mañana → 13:00 mediodía → 18:00 tarde →
  20:12 ocaso → 21:06 crepúsculo → 21:48 noche. Los valores de alba, ocaso y crepúsculo están en `configurador.html` (`KEYS_DIA`).
- **Siempre día:** fijo en el color de las 9:30.
- **Siempre noche:** Bosque fijo.

## El círculo que respira

- Mismo **tamaño (168 pt) y mismo lugar** en Inicio, Decidir y En curso: centro horizontal, un poco por encima del centro vertical (centro óptico).
- **Sin línea.** Es solo el apoyo del halo. El interior es del color del fondo.
- **Respiración de 7 s:** 3 s inhala, 4 s exhala, con aceleración suave.
- **Halo hacia afuera:** nace pegado al borde con el color pleno del halo (unos 5 pt) y se desvanece en ~22 capas casi transparentes,
  sin borde final. En su máximo se extiende ~1,2 veces el radio.
- **Halo hacia adentro:** siempre presente, más corto (9 a 14 pt, más al exhalar), también difuso y sin borde.
- **Forma irregular:** el borde es una suma de ondas suaves (2 a 5 lóbulos). En cada respiración la forma cambia y gira muy despacio.
- En "En curso" y mientras se dicta, el halo usa el color de energía. Al dictar, **reacciona a la voz**: crece con lo fuerte que se habla.
- Cuando la pantalla se llena de color (Empiezo o Ahora no), el centro del círculo se desvanece: no queda ningún círculo claro encima.
- Con "Reducir movimiento" activado en el iPhone, el halo queda quieto.

## Pantallas

### Inicio (pantalla principal)
- **Arriba:** listado y calendario en la esquina izquierda; cajón (inbox e ideas) y ajustes en la derecha.
  Debajo, la pista "Tocá y decí lo que tenés en la cabeza".
- **El círculo es el micrófono**, con un ícono chico. Un toque y ya escucha, sin pasos extra: no se muestra el texto en vivo,
  solo el halo que reacciona a la voz y un botón "Listo". Mientras se ordena lo dictado, un **cerebro que late** en el centro.
  Después sube la revisión ("Entendí 3 cosas") para cambiar lo que haga falta antes de guardar.
  Manteniendo apretado el círculo se abre la versión para escribir.
- **Fichero abajo:** las próximas tres cosas en tarjetas apiladas (la primera entera, las otras asoman debajo). Cada tarjeta
  tiene la categoría en su color, el título y la cuenta regresiva ("para empezar" o "para salir"); la primera muestra también
  lugar, notas y, si es de un proyecto, su barra. Un toque las despliega y aparece **"Ver todo"**, que abre el listado.
  A los 8 s vuelven solas.

### Decidir (a la hora del slot)
- En el centro del círculo, **dos flechitas iguales y chicas** (arriba y abajo).
- **El círculo sigue al dedo** en vertical; de costado se mueve con un elástico suelto (60 pt como máximo), así el recorrido es una curva.
- **Hacia arriba → Empiezo.** La pantalla se va llenando de verde energía desde el círculo, en proporción a lo que subís,
  hasta el borde de arriba. Empieza al llegar, o al soltar pasada la mitad.
- **Hacia abajo hasta el borde (170 pt) y sostener 2 s → Ahora no.** Mientras sostenés, la pantalla se llena de salvia apagada.
  Si subís el dedo antes de los 2 s, vuelve a su lugar.
- "Empiezo" y "Ahora no" aparecen **fijos en el centro**, en el blanco cálido.
- Indicaciones mínimas abajo ("deslizá: empiezo · bajá y sostené: ahora no") solo las primeras veces.

### ¿Cuándo, entonces? (después de "Ahora no" o "Paro por hoy")
- Primero, una transición que aparece de golpe: "Está bien, lo movemos." solo, grande e itálica, en blanco cálido sobre la
  salvia apagada. El texto rota: "Tranqui, buscamos otro momento.", "No pasa nada, reagendamos.", "Todo bien, va para más tarde.", "Dale, lo acomodamos."
- Después, la **tarea en grande** arriba, "Lo movemos." chico e itálica justo debajo y una tarjeta con la pregunta
  "¿Cuándo, entonces?" (más chica y con aire) y las opciones. Poca información: la persona probablemente está cansada.
- **3 slots concretos** que respetan el calendario y el horario del lugar. Al tocar uno se agranda, muestra un renglón de por qué y el botón **Agendar**.
- **Otra hora:** días disponibles y horarios libres; los ocupados aparecen tachados.
- **Ya no la voy a hacer:** archiva la tarea (se puede recuperar).

### Listado
- Pestañas: **Hoy** (la que se ve primero: todo junto por hora, incluidas las sesiones de proyecto), **Tareas**, **Citas** y **Proyectos**.
- Inbox e ideas no están acá: viven en el **cajón**, que se abre con el ícono de bandeja de Inicio. Es una sola lista con dos secciones.

### Proyectos
- **En el listado, una sola tarjeta lisa por proyecto:** "PROYECTO" en su color y, arriba a la derecha, las etapas completas ("1/4");
  el nombre; "Ahora: Embalar" con "faltan 22 días" en el mismo renglón; la **línea de tiempo** del inicio al fin (las divisiones son
  las etapas y la marca es hoy) y la próxima sesión.
- **Adentro:** etapas que se abren (al entrar, solo la actual, con sus sesiones). Las siguientes dicen "Las sesiones de esta etapa se
  arman cuando llegues a ella". **Manijas ≡ siempre visibles** para reordenar etapas y sesiones: una sesión que se mueve toma el
  horario del lugar al que va; una etapa que se mueve mantiene lo que dura y las fechas se reparten de nuevo.
- **Ficha de la etapa** (lápiz): nombre y cuánto dura, en días o en horas. Las que siguen se corren. Si el plan se pasa de la
  fecha final, ofrece correr la fecha final o achicar las etapas que siguen.
- **Nuevo proyecto:** nombre, dos campos (Empieza y Termina) que abren un calendario para marcar el rango y muestran cuánto dura,
  notas y el botón **"Armar las etapas"**. Las propuestas se renombran, se reordenan, se quitan o se agregan antes de crear.

### En curso
- Ya no ocupa la pantalla principal: es la primera tarjeta del fichero (borde verde energía, "quedan 23:10") y se abre al tocarla.
- Adentro: solo la cuenta regresiva dentro del círculo, sin barra ni arco de progreso.
- Abajo, la **ruleta de pasos**: la última tachada siempre visible y las dos siguientes debajo; deslizando se ve el historial o lo que viene.
- Aviso suave 5 min antes del final.

### Fin del slot
- Primero la **recompensa**, grande y al centro: círculo con tilde y ondas de energía, y un mensaje de ánimo que varía.
- Al tocar **Terminé** (al final o antes, desde En curso): primero la pantalla entera en verde energía con un mensaje grande en blanco
  cálido que rota ("¡Bien ahí!", "¡Eso!", "¡Buena, crack!", "¡Vamos!", "¡Bien metida!"), aparece de golpe; después la celebración con el
  halo verde grande, un brote que crece, "Listo." arriba y los minutos de foco.
- Después "¿Cómo seguimos?" con íconos lineales: brote (Terminé), reloj redondo (Necesito más: +10, +15, +30), luna (Paro por hoy).
- Si la extensión choca con el slot siguiente, aviso en ocre con "Correrlo" o una extensión menor.

### Aviso (notificación)
- Notificación común de iOS (no se puede colorear ni bloquear).
- Si se descarta, vuelve a los **3 minutos**. Al **tercer descarte** el slot se cierra como "Ahora no" y al abrir la app aparece "¿Cuándo, entonces?".
- Los tres avisos se programan de antemano y se cancelan apenas el usuario decide.

## Textos clave

"Tocá y decí lo que tenés en la cabeza" · "Ver todo" · "Lo próximo" · "Es la hora" · "Empiezo" · "Ahora no" · "Está bien, lo movemos." · "¿Cuándo, entonces?" ·
"Agendar" · "Otra hora" · "Ya no la voy a hacer" · "¿Cómo seguimos?" · "Terminé" · "Necesito más" · "Paro por hoy" ·
"Armar las etapas" · "Ordenar".

**Regla:** la interfaz nunca nombra a la IA que está detrás (Claude). Solo Ajustes la menciona, porque ahí se carga la clave.
