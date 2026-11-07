# Guía de diseño · "Respiro"

Estética cerrada el 2026-11-06. La muestra interactiva de referencia es [`configurador.html`](configurador.html)
(abrila en un navegador): todo lo que dice esta guía está implementado ahí y es la fuente para pasarlo a SwiftUI.

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

### Apariencia (pantalla de Ajustes)

- **Automático:** los colores cambian de a poco con la hora, sin saltos, mezclando entre estos puntos:
  5:00 noche → 5:48 crepúsculo → 6:36 alba → 8:00 mañana → 13:00 mediodía → 18:00 tarde →
  20:12 ocaso → 21:06 crepúsculo → 21:48 noche. Los valores de alba, ocaso y crepúsculo están en `configurador.html` (`KEYS_DIA`).
- **Siempre día:** fijo en el color de las 9:30.
- **Siempre noche:** Bosque fijo.

## El círculo que respira

- Mismo **tamaño (168 pt) y mismo lugar** en Espera, Decidir y En curso: centro horizontal, un poco por encima del centro vertical (centro óptico).
- **Sin línea.** Es solo el apoyo del halo. El interior es del color del fondo.
- **Respiración de 7 s:** 3 s inhala, 4 s exhala, con aceleración suave.
- **Halo hacia afuera:** nace pegado al borde con el color pleno del halo (unos 5 pt) y se desvanece en ~22 capas casi transparentes,
  sin borde final. En su máximo se extiende ~1,2 veces el radio.
- **Halo hacia adentro:** siempre presente, más corto (9 a 14 pt, más al exhalar), también difuso y sin borde.
- **Forma irregular:** el borde es una suma de ondas suaves (2 a 5 lóbulos). En cada respiración la forma cambia y gira muy despacio.
- En "En curso", el halo usa el color de energía.
- Con "Reducir movimiento" activado en el iPhone, el halo queda quieto.

## Pantallas

### Espera (pantalla principal)
- Solo el próximo slot: título, hora y duración, y "comienza en 4:32" dentro del círculo.
- Deslizando al costado se ven los **dos siguientes**, cada uno con su cuenta. A los 6 s vuelve sola al próximo.

### Decidir (a la hora del slot)
- En el centro del círculo, un **punto que late** (color entre el primario y el halo; nunca el verde más intenso).
- **Apretar y deslizar hacia arriba (90 pt) → Empiezo.** Mientras subís, "Empiezo" aparece dentro del círculo y la pantalla se tiñe de energía.
- **Apretar y quedarse quieto 1,5 s → Ahora no.** Una línea rodea el círculo y "Ahora no" aparece dentro.
  Si el dedo se mueve más de 10 pt, cuenta como deslizar.
- Indicaciones mínimas abajo ("deslizá: empiezo · mantené: ahora no") solo las primeras veces.

### ¿Cuándo, entonces? (después de "Ahora no" o "Paro por hoy")
- La tarea en grande y "Está bien, lo movemos." en verde e itálica. Poca información: la persona probablemente está cansada.
- **3 slots concretos** que respetan el calendario y el horario del lugar. Al tocar uno se agranda, muestra un renglón de por qué y el botón **Agendar**.
- **Otra hora:** días disponibles y horarios libres; los ocupados aparecen tachados.
- **Ya no la voy a hacer:** archiva la tarea (se puede recuperar).

### En curso
- Solo la cuenta regresiva dentro del círculo, sin barra ni arco de progreso.
- Abajo, la **ruleta de pasos**: la última tachada siempre visible y las dos siguientes debajo; deslizando se ve el historial o lo que viene.
- Aviso suave 5 min antes del final.

### Fin del slot
- Primero la **recompensa**: círculo con tilde y ondas de energía, y un mensaje de ánimo que varía.
- Después "¿Cómo seguimos?" con íconos lineales: brote (Terminé), reloj redondo (Necesito más: +10, +15, +30), luna (Paro por hoy).
- Si la extensión choca con el slot siguiente, aviso en ocre con "Correrlo" o una extensión menor.

### Aviso (notificación)
- Notificación común de iOS (no se puede colorear ni bloquear).
- Si se descarta, vuelve a los **3 minutos**. Al **tercer descarte** el slot se cierra como "Ahora no" y al abrir la app aparece "¿Cuándo, entonces?".
- Los tres avisos se programan de antemano y se cancelan apenas el usuario decide.

## Textos clave

"Lo próximo" · "comienza en" · "Es la hora" · "Empiezo" · "Ahora no" · "Está bien, lo movemos." · "¿Cuándo, entonces?" ·
"Agendar" · "Otra hora" · "Ya no la voy a hacer" · "¿Cómo seguimos?" · "Terminé" · "Necesito más" · "Paro por hoy".
