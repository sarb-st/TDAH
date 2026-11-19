# AppTDAH

App de iPhone (SwiftUI) para personas con TDAH: dictás lo que tenés en la cabeza, la app lo ordena en tareas,
citas, proyectos e ideas, y a la hora de cada tarea te empuja a empezar. La fecha y hora de compilación está en
Ajustes → Versión, para confirmar que estás viendo la última versión.

La app se compila en una Mac en la nube (GitHub Actions), sin necesidad de tener Mac ni Xcode.

## Descarga directa (desde el iPhone)

👉 **https://github.com/sarb-st/TDAH/releases/latest/download/AppTDAH.ipa**

Este enlace siempre apunta a la última versión compilada.

---

## Qué hace cada archivo

| Archivo | Para qué sirve |
|---|---|
| `AppTDAH/AppTDAHApp.swift` | Arranque de la app y la pantalla raíz, que decide qué mostrar en cada momento. |
| `AppTDAH/Modelo/Tarea.swift` | Qué se guarda en el iPhone: tareas, pasos, el rastro de cada slot, los renglones de listas e ideas y tu gente con su hilo. |
| `AppTDAH/Logica/Perfil.swift` | Lo tuyo: tu día, suave o firme, objetivos y horarios fijos (turnos que alternan, días distintos, la semana elegida). |
| `AppTDAH/Logica/Repeticion.swift` | Las reglas para repetir una tarea y cuándo toca la próxima vez. |
| `AppTDAH/Logica/MotorSlots.swift` | Las reglas: qué pantalla toca, los avisos, los choques y los huecos libres para "¿Cuándo?". |
| `AppTDAH/Diseno/Paleta.swift` | Los colores de la estética "Respiro" y cómo cambian a lo largo del día. |
| `AppTDAH/Diseno/CirculoQueRespira.swift` | El círculo que respira y las piezas comunes de las pantallas. |
| `AppTDAH/Diseno/Categoria.swift` | Los colores de cada categoría, las tarjetas con banda de color y la lista que se reordena con manijas. |
| `AppTDAH/Logica/Plan.swift` | Las cuentas de las etapas de un proyecto: duraciones, correr, achicar, repartir y reordenar. |
| `AppTDAH/Pantallas/Inicio.swift` | Inicio: el círculo (micrófono), el halo imán con las cuatro medias pastillas y el fichero con la importante. |
| `AppTDAH/Pantallas/Principal.swift` | Decidir, ¿Cuándo?, En curso, Fin del slot y las transiciones. |
| `AppTDAH/Pantallas/Vos.swift` | Vos: tu foto y tu día, objetivos, suave o firme y horarios fijos. |
| `AppTDAH/Pantallas/Semana.swift` | ¿Qué te toca esta semana? (domingos a las 20). |
| `AppTDAH/Pantallas/Tuyos.swift` | Los tuyos: con quién estar presente, cómo, de qué hablar y el hilo de lo que te contaron. |
| `AppTDAH/Pantallas/Preparar.swift` | Preparar mañana: el ritual de las 20 en cuatro pasos y el brote del cierre. |
| `AppTDAH/Pantallas/Importante.swift` | La importante a la mañana (firme o suave) y el empujoncito cuando un objetivo queda quieto. |
| `AppTDAH/Pantallas/Repetir.swift` | La pantalla para repetir una tarea, dictada o a mano. |
| `AppTDAH/Pantallas/Cajon.swift`, `Fichas.swift` | El cajón (listas, ideas e inbox), sus fichas y Convertir. |
| `AppTDAH/Pantallas/Agenda.swift` | El listado con pestañas, el calendario por día y el detalle de cada tarea. |
| `AppTDAH/Diseno/Haptica.swift` | Las vibraciones (se apagan en Ajustes). |
| `AppTDAH/Pantallas/Lugar.swift` | Las sugerencias de lugares al escribir y el recálculo de la hora de salida desde donde estás. |
| `AppTDAH/Pantallas/Edicion.swift` | Nueva tarea, Ajustes y Diagnóstico. |
| `AppTDAH/Pantallas/Captura.swift` | Dictar lo que tenés en la cabeza y revisar antes de guardar: cuándo, hora, duración, lugar y tus pasos. |
| `AppTDAH/Pantallas/Proyectos.swift` | Proyectos: tarjeta, etapas que se abren y se reordenan, ficha de cada etapa, fechas con calendario y replanteo. |
| `AppTDAH/Servicios/IA.swift` | La conexión con Claude (clasificar dictados y replanear proyectos) y la clave guardada en el Keychain. |
| `AppTDAH/Servicios/Dispositivo.swift` | Dictado por voz, tiempo de viaje con Mapas y el espejo en el calendario del iPhone. |
| `AppTDAH/Servicios/Alarmas.swift` | Las alarmas que suenan aunque el iPhone esté en silencio (iOS 26 en adelante). |
| `AppTDAH/Servicios/Widgets.swift` | Le deja anotado al widget "Lo que viene" lo próximo cada vez que cambia algo. |
| `AppTDAHWidgets/` | Los widgets: Hablar, Escribir y Lo que viene (con cuenta regresiva y flechitas para pasar). |
| `Compartido/` | Lo que usan la app y los widgets: lo próximo, cómo se dibuja cada widget y la carpeta compartida. |
| `AppTDAH/Servicios/Servicios.swift` | Avisos, firma, copia de seguridad, registro de errores y datos de muestra para las capturas. |
| `AppTDAH/Fuentes/` | La tipografía Fraunces y su licencia libre (SIL Open Font License). |
| `AppTDAH/Sonidos/` | La campanita corta y suave de la alarma (hecha para esta app). |
| `AppTDAH/Textos.swift` | Cómo se escribe la fecha de compilación. |
| `AppTDAH/BuildInfo.swift` | Fecha y versión de compilación; la nube lo reescribe en cada compilación. |
| `AppTDAHTests/` | Pruebas automáticas de las reglas, los colores y los textos. |
| `project.yml` | Receta del proyecto: XcodeGen la usa para crear el proyecto de Xcode en la nube. |
| `.github/workflows/compilar.yml` | Instrucciones para la Mac en la nube: probar, compilar, empaquetar y publicar. |
| `.gitignore` | Lista de archivos que nunca se suben (compilaciones, archivos temporales, claves). |
| `diseno/DISENO.md` | Guía de diseño: colores, tipografía, el círculo que respira y cada pantalla. |
| `diseno/configurador.html` | Muestra interactiva de la estética (se abre en el navegador). |
| `diseno/maqueta-a.html` a `-f` | Las maquetas aprobadas: inicio y decidir; colores, listado y cajón; proyectos; Vos y widgets; la importante y los tuyos; ideas y revisión al dictar. |
| `CLAUDE.md` | Reglas permanentes del proyecto (por ejemplo: nunca subir claves ni datos personales). |
| `README.md` | Este documento. |

## Cómo ver si la compilación funcionó

1. Entrá a **https://github.com/sarb-st/TDAH/actions**
2. Cada vez que se sube un cambio a `main` aparece una fila nueva llamada **"Compilar y publicar"**.
   - 🟡 círculo amarillo: todavía está compilando (tarda unos 5–15 minutos).
   - ✅ tilde verde: salió bien y el `.ipa` ya está publicado.
   - ❌ cruz roja: algo falló. Tocá la fila y después el paso con la cruz para ver el error.
3. Las versiones publicadas están en **https://github.com/sarb-st/TDAH/releases**

## Cómo instalarla en el iPhone con SideStore

**Antes, una sola vez:** tenés que tener SideStore instalado y funcionando en el iPhone
(con tu Apple ID gratis). La guía oficial está en https://docs.sidestore.io

Después, cada vez que quieras instalar una versión nueva:

1. En el iPhone, abrí **Safari** y entrá al enlace de *Descarga directa* de arriba.
2. Safari pregunta si querés descargar `AppTDAH.ipa` → tocá **Descargar**.
   El archivo queda en la app **Archivos → Descargas**.
3. Abrí **SideStore** → pestaña **My Apps** → botón **+** (arriba a la izquierda).
4. Elegí `AppTDAH.ipa` desde **Descargas**.
5. SideStore la firma con tu Apple ID y la instala. Aparece en tu pantalla de inicio.
6. Abrila y mirá en **Ajustes → Versión** la fecha y hora de la compilación.

Si la fecha coincide con la de la última compilación en GitHub, estás viendo la versión más nueva.

**Límites de la cuenta gratis de Apple:**
- Las apps vencen a los **7 días**. Abrí SideStore y tocá **Refresh All** antes de que venzan.
- Podés tener hasta **3 apps** instaladas así a la vez (SideStore cuenta como una).
- Instalar una versión nueva reemplaza a la anterior.
- **Los widgets cuentan como una app más.** SideStore + AppTDAH + sus widgets = 3. Si al instalar SideStore pregunta
  si querés conservar las extensiones (*Keep App Extensions*), elegí que sí; si no, la app anda igual pero sin widgets.

### Cómo agregar los widgets

1. En la pantalla de inicio, mantené apretado un espacio vacío hasta que los íconos tiemblen.
2. Tocá **Editar → Agregar widget** (o el **+** arriba a la izquierda) y buscá **AppTDAH**.
3. Elegí entre:
   - **Hablar** (chico): un toque y dictás. También va redondo en la pantalla de bloqueo.
   - **Escribir** (mediano): un renglón; tocás y se abre la app con el teclado listo. También va en la pantalla de bloqueo.
   - **Lo que viene** (chico, mediano o grande): lo próximo con su cuenta regresiva. Las flechitas ‹ › pasan a lo
     siguiente sin abrir la app. Si es la importante, tiene borde dorado.

   Si tenías el widget mediano de Captura, quitalo y agregá Escribir: ese tamaño ahora es de Escribir.

Si "Lo que viene" queda en "Nada por ahora" aunque tengas cosas cargadas, abrí la app una vez. Si sigue igual,
copiá el registro de **Ajustes → Diagnóstico** (la línea "Widgets:") y pegalo en Claude Code.

## Cómo conseguir la clave de Claude (una sola vez)

La app usa Claude para ordenar lo que dictás. Cada captura cuesta centavos de dólar.

1. Entrá a **https://console.anthropic.com** desde la compu y creá una cuenta (podés usar tu Google).
2. En **Billing**, cargá crédito (con 5 dólares alcanza para mucho tiempo). Podés poner un límite mensual.
3. En **API Keys**, tocá **Create Key**, ponele de nombre "AppTDAH" y copiá la clave (empieza con `sk-ant-`).
4. Mandátela al iPhone (por ejemplo por notas o mail a vos mismo), abrí la app → **Ajustes** → **Inteligencia artificial**, pegala y tocá **Guardar la clave**.

La clave queda solo en el Keychain del iPhone: no está en el código ni en GitHub. Si alguna vez la perdés o se filtra, borrala en la consola y creá otra.

## Si SideStore da el error -80045 al iniciar sesión

Es un rechazo de Apple, no un problema de tu contraseña. Lo que funcionó, en SideStore:

1. **Settings → User Customizations:** apagá **On-Device Anisette**.
2. **Anisette Servers:** elegí **SideStore (New)** y apagá **Enable Auto Rotation**.
3. **User Customizations → Anisette Client Configuration → Remote Server Sync:** tocá **Fetch** y después **Save as Overrides**.
4. **User Customizations:** tocá **Reset adi.pb**.
5. Con **LocalDevVPN activada**, iniciá sesión una sola vez. Para el código, elegí **dispositivo Apple**, no SMS.

## Seguridad

Este repositorio es público. No contiene claves, contraseñas ni datos personales, y no debe
contenerlos nunca. La compilación se publica con el permiso automático de GitHub, sin claves guardadas.
