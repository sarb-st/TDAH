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

---

## Ajustes del 2026-11-19 (maquetas D, E y F aprobadas)

Las maquetas [`maqueta-d.html`](maqueta-d.html), [`maqueta-e.html`](maqueta-e.html) y [`maqueta-f.html`](maqueta-f.html) muestran solo lo
último que se revisó; lo aprobado antes se describe acá. **Nada de degradés**: colores lisos de la paleta.

### Colores nuevos
- **Dorado de la importante:** borde `#D9B26E`, fondo `#F1E3C2`, texto `#7A5E22`.
- **Lista:** salvia agua `#9DB5AC` (tinta `#5E8378`).
- **Turnos de trabajo:** mañana salvia agua `#5E8378`, tarde azul `#6E86A0`.

### Inicio
- **Arriba:** a la izquierda la personita (**Vos**), a la derecha el engranaje (**Ajustes**).
- **Halo imán:** al apoyar el dedo en cualquier lugar, el halo se estira hacia el dedo sin dejar de respirar (dos círculos
  unidos por sus tangentes). El círculo no se mueve.
- **Cuatro medias pastillas** asoman desde los bordes: izquierda calendario, derecha listado, arriba cajón, abajo todo lo que viene.
  Al apoyar el dedo entran enteras con ícono y nombre. Cuando el halo toca una, se enciende (tic de vibración); al soltar se abre.
- Tocar el círculo: hablar. Mantenerlo apretado: escribir.
- **Terminé** en la primera tarjeta del fichero cuando hay algo en curso ("Ya terminó" en una cita), y también adentro de la tarjeta abierta.
- **La importante en el fichero:** borde dorado si está entre las tres próximas (suave y firme). En firme, si hay otra antes,
  asoma detrás del fichero, a la izquierda, una **solapa dorada** "★ 11:00 · título". No hay renglón fijo arriba.

### Vos (la personita)
- Foto (tuya o cualquiera; sin foto, la inicial) y nombre (va en los avisos a tu persona).
- **Tu día:** a qué hora te levantás y te acostás; cuándo rendís más (mañana, tarde o noche) para ubicar lo pesado.
- **Lo que te importa:** Objetivos (pantalla propia) y **Con la importante: Suave / Firme**.
- **Tu semana:** **Horarios fijos**. Minutos de foco.
- **Tu gente:** persona de accountability y **Los tuyos**.

### Ajustes (el engranaje)
Apariencia, sonido del aviso, vibraciones, casa y ciudad, clave de Claude, calendario y copia de seguridad, diagnóstico.

### Horarios fijos
- Lo ocupado: ahí la app no propone nada. Si el usuario carga algo ahí, lo deja.
- **Trabajo:** turno mañana (06:00–14:00) y turno tarde (14:00–22:00), editables; qué días (L a D); **días distintos**
  (tocando un día: "entrás/salís X antes o después", vale para los dos turnos; queda un puntito); **Alterno cada semana** (interruptor estándar).
- Otros fijos (por ejemplo, un deporte los sábados de 10:00 a 12:30) y "+ Agregar un horario fijo".

### Esta semana (domingos 20:00, dentro de Preparar mañana; también desde Horarios fijos)
- "¿Qué te toca esta semana?" y las fechas, con aire.
- Renglón **Turno** con selector chico Mañana | Tarde (si alterna, ya viene elegido; debajo lo dice).
- Los 7 días como **letras con número**: fondo blanco, borde y letra del color del turno; libres con borde punteado; puntito dorado si se cambió.
  Tocando uno se abre debajo: Mañana / Tarde / Libre y Entro / Salgo (renglones bajos con − y +). Cambia solo ese día.
- "Contame la semana" por voz.

### Repetir
- Se dicta ("contámelo como te salga") o se elige: Todos los días · Algunos días (L a D) · Cada tanto (cada N días o semanas:
  "la hacés una vez y la siguiente es N después") · Una vez por mes (el día N).
- **La hora siempre** (y lo que dura). Hasta cuándo: Siempre · Unos meses (N) · Hasta una fecha (pastillita gris con la fecha
  que abre un calendario chico) · Unas veces (N).
- Controles − y + del stepper de iOS. Renglón "Cada 2 semanas" con letra del sistema y número de ancho fijo.
- Abajo, 6 semanas de calendario con los días que se encienden y el total de veces.

### Widgets
- **Lo que viene:** franja de color de la categoría arriba con la etiqueta en blanco ("TAREA · 09:45"), flechitas ‹ › y puntitos
  para pasar a lo siguiente y volver. Título en un renglón (si es largo, la app arma un **título corto**; el completo queda en la tarea).
  Abajo: la cuenta en una columna de ancho fijo (desde 1 h "1:12 h", desde 6 h la hora) y a la derecha los próximos pasos o, si no hay, lugar y notas.
  Chico, mediano y grande (con "Después"). **Borde dorado** cuando lo que viene es la importante.
- **Hablar:** chico, solo el micrófono centrado; redondo en la pantalla de bloqueo.
- **Escribir:** mediano bajo, un renglón "Contame en qué estás…"; rectangular en la pantalla de bloqueo. Abre la app con el teclado listo.
  (iOS no deja que la app haga transparente el fondo del widget.)

### Vibraciones
Empiezo: un golpe firme. Ahora no: suave que crece mientras se sostiene y un golpe al cerrar. Terminé: dos toquecitos.
Tachar un paso: un tic leve. Halo en una pastilla: un tic. Dictado: un tic al empezar y otro al terminar. También en silencio; se apaga en Ajustes.

### Preparar mañana (aviso a las 20:00; si no se abre, espera esa noche al abrir la app)
1. **Mañana, viernes 20:** un renglón de ánimo que cambia según cuánto hay y la línea del día (salidas, citas, tareas, turnos).
2. **¿Qué dejamos listo?:** primero la tarea (chica) y después lo que hay que llevar o tener listo. Cada cosa: **Listo** o
   **Mañana** (avisa media hora antes de salir o de la tarea). Orden por hora.
3. **La importante de mañana:** una sola; las de los objetivos primero. Puede sugerir un mejor horario, sin consecuencia si no se acepta.
   En firme hay que elegir una para poder cerrar.
4. **Mañana está armado.** El brote aprobado de la celebración (sin "Listo."), la primera cosa (con lo que hay que llevar) y la importante.

### La importante: suave o firme (se elige en Vos)
- **Suave:** su ★ y borde dorado. La primera vez que se abre la app en el día baja una tarjetita dorada "Hoy, lo importante" que se va sola.
- **Firme:**
  - La primera vez del día: "Buen día. Hoy lo importante es:" con su tarjeta. Si hay un hueco libre de verdad antes (respetando
    horarios fijos y lo cargado), ofrece adelantarla; si no, solo la recuerda.
  - "Ahora no" se sostiene **4 s** (en vez de 2) con vibración que crece. Después la transición de siempre y "¿Cuándo, entonces?"
    con la etiqueta ★ La importante y borde dorado; propone solo horas de hoy y avisa a la persona de accountability.
  - La app nunca propone otra cosa en el horario de la importante.
- **Cargar algo encima** (igual en los dos modos): "Ese horario es de la importante. Te propongo las 12:30, apenas termina." · Usar 12:30 · Ponerla igual (la importante se corre).

### Objetivos
- Hasta 3, con nombre editable y minutos de foco de la semana. "Estar presente con los míos" lleva la gente.
- Lo demás se ordena solo en áreas: Casa, Cuidado personal, Pareja, Trámites y papeles, Trabajo, Tiempo libre.
- "Lo último que ordenó": tocando la etiqueta se corrige y la app aprende para lo parecido.

### Empujoncito (si pasan un par de días sin nada de un objetivo)
Pantalla propia, fondo liso. Ícono: **arco que avanza**. "¿Le damos un empujoncito a lo tuyo?", tarjeta con barras de la semana,
un comentario cálido sobre lo último que hizo y dos sugerencias con **Agendar**. "Ahora no" · "Avisame menos seguido".

### Los tuyos (estar presente)
- Personas elegidas de Contactos, con cada cuánto querés hablar. La app no puede leer llamadas ni WhatsApp.
- Círculos: con foto, la foto; sin foto, la letra y la circunferencia en el color. El aro se llena al hablar, se vacía con los días
  y gira despacio; vacío = "ya toca". Leyenda chica debajo.
- Al elegir a alguien: su **hilo** (lo que te contó, en qué quedaron), **¿Cómo?** Llamada · Audio · Mensaje · En persona,
  **¿De qué querés hablar?** (con temas sugeridos del hilo), cuándo y **Agendar**. Nunca sugiere cosas de proyectos ni tareas.
- Al terminar (o con "Ya hablé"), pregunta "¿Qué te contaron? ¿En qué quedaron?" y lo guarda en el hilo.

### Cajón
Orden: **Listas** ("pongámoslo en papel"), **Ideas** ("cosas para pelotear"), **Inbox** ("dame más data").

- **Lista:** título, renglones con círculo para tachar, **+** en cada renglón para agregar adentro (un nivel), tachar todo lo de
  adentro tacha el de arriba, rayitas para mover. Intro = "Siguiente" (deja el teclado abierto) y botón Sumar. Anillo de progreso con
  frase. Al completarse: Archivarla · Usarla de nuevo · Dejarla así. No cuenta minutos de foco. Convertir: una tarea con estos pasos ·
  un proyecto con estas etapas · una acción por renglón.
- **Idea:** cabecera lila lisa con el tema, título editable, tu audio y lo que dijiste como cita. **Lo que la mueve:** una sola lista;
  cada renglón con la marca de voz (lo dictaste) o ✦ (sugerido); "✦ abrir" agrega cosas más chicas adentro (Sumar o ×); todo se
  reordena. Sumar un renglón escribiendo (Intro o Sumar, sin micrófono). "¿Vamos con algunos pasos?" propone pasos en un recuadro; los
  sumados entran al final de la lista y también se abren. Convertir.
- **Inbox:** cabecera arena, lo que dijiste, tu audio y "se archiva solo en N días". La app pregunta "No me quedó claro. ¿Qué es…?" con
  2–3 opciones (categoría y título); "O contame más"; Convertir; Archivar. "Convertir" reemplaza a "Ordenar": primero "Que lo ordene la app", después elegir.

### Revisión al dictar
"Recién dictaste", lo dicho en dos renglones (se abre al tocar), el título en verde liso y **cuatro tarjetas grandes: Cuándo, Hora,
Dura, Dónde**, que se tocan para cambiar. Pasos compactos: marca de voz o ✦, sugeridos con Sumar, "✦ Parece grande · Partir" (los pasos
más chicos entran en la lista como sugeridos), × siempre, rayitas para mover. Debajo: "+ Escribir un paso" y "✦ Sugerime uno" (entra
donde corresponde). Si el usuario dicta pasos, la IA usa exactamente esos.


## Ajustes del 2026-11-20 (maqueta G aprobada)

Salieron de usar la app unos días. Muestra en `diseno/maqueta-g.html`.

- **Círculo:** baja de 168 a 124 pt en todas las pantallas (sigue siempre del mismo tamaño y en el mismo lugar). Deja aire hasta las pastillas.
- **Halo imán:** el verde es el halo mezclado con el salvia (más oscuro), opacidad 0,62 y difuminado 8. La gota llega casi hasta el dedo (94 % de la distancia, hasta 250 pt), se adelgaza poco en la punta y el círculo se inclina hacia el dedo (16 %).
- **Pastilla de abajo:** asoma por encima de las tarjetas del fichero (la mitad queda detrás), como la de arriba desde el borde. Al apoyar el dedo sube entera con aire. Si asoma la solapa dorada, se corre por encima. Abre **Ver todo** (el listado en Hoy).
- **Fichero:** tocar las tarjetas las despliega (las tres); desplegadas, tocar una la abre. Ya no hay botón "Ver todo".
- **Escribir:** sin micrófono ni círculo (si elegiste escribir es porque no podés hablar): la pregunta, la caja grande, "Cargar a mano" y "Listo" pegado arriba del teclado. El teclado se baja tocando afuera de la caja o arrastrando hacia abajo, sin botón. Desde el widget de hablar con algo pendiente, sí lleva micrófono.
- **Decidir:** en el primer cuarto del gesto se pinta el círculo entero; después el color sale a la pantalla. Mientras se pinta, el halo toma el mismo color y el borde claro de adentro se apaga: lleno, no se nota la circunferencia.
- **Widget grande (opción A):** título; debajo, la cuenta (con la hora de inicio y fin) y, separados por una línea fina, los pasos (15 pt, hasta 4; si hay más, "y N más"). El aire queda antes de "Después".
  - Con lugar y nota: dos cajitas con rótulo e ícono (el lugar más angosto); la nota en un renglón con "…".
  - Solo lugar (o solo nota): una cajita baja con el rótulo y el texto en el mismo renglón; "Después" muestra 4.
  - Sin pasos: el lugar (y la nota corta) a la derecha de la cuenta, centrados en el alto. Una nota larga pasa abajo, a todo el ancho, hasta 3 renglones.
- **Hora del widget:** siempre en 24 h.
- **"Casa" en el lugar:** usa la dirección de Ajustes; al escribir, "Casa" aparece primera en las sugerencias.
