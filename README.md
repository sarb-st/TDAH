# AppTDAH

App de iPhone (SwiftUI) en etapa de prueba. Por ahora solo muestra **"Hola"** y la fecha y hora
en que fue compilada, para confirmar que estás viendo la última versión.

La app se compila en una Mac en la nube (GitHub Actions), sin necesidad de tener Mac ni Xcode.

## Descarga directa (desde el iPhone)

👉 **https://github.com/sarb-st/TDAH/releases/latest/download/AppTDAH.ipa**

Este enlace siempre apunta a la última versión compilada.

---

## Qué hace cada archivo

| Archivo | Para qué sirve |
|---|---|
| `AppTDAH/AppTDAHApp.swift` | Arranque de la app y la pantalla raíz, que decide qué mostrar en cada momento. |
| `AppTDAH/Modelo/Tarea.swift` | Qué se guarda en el iPhone: tareas, pasos y el rastro de cada slot. |
| `AppTDAH/Logica/MotorSlots.swift` | Las reglas: qué pantalla toca, los avisos, los choques y los huecos libres para "¿Cuándo?". |
| `AppTDAH/Diseno/Paleta.swift` | Los colores de la estética "Respiro" y cómo cambian a lo largo del día. |
| `AppTDAH/Diseno/CirculoQueRespira.swift` | El círculo que respira y las piezas comunes de las pantallas. |
| `AppTDAH/Pantallas/Principal.swift` | Las pantallas principales: Espera, Decidir, ¿Cuándo?, En curso, Fin del slot y las transiciones. |
| `AppTDAH/Pantallas/Agenda.swift` | El listado de tareas en tarjetas, el calendario por día y el detalle de cada tarea. |
| `AppTDAH/Pantallas/Edicion.swift` | Nueva tarea, Ajustes y Diagnóstico. |
| `AppTDAH/Servicios/Alarmas.swift` | Las alarmas que suenan aunque el iPhone esté en silencio (iOS 26 en adelante). |
| `AppTDAH/Servicios/Servicios.swift` | Avisos, firma, copia de seguridad, registro de errores y datos de muestra para las capturas. |
| `AppTDAH/Fuentes/` | La tipografía Fraunces y su licencia libre (SIL Open Font License). |
| `AppTDAH/Textos.swift` | Cómo se escribe la fecha de compilación. |
| `AppTDAH/BuildInfo.swift` | Fecha y versión de compilación; la nube lo reescribe en cada compilación. |
| `AppTDAHTests/` | Pruebas automáticas de las reglas, los colores y los textos. |
| `project.yml` | Receta del proyecto: XcodeGen la usa para crear el proyecto de Xcode en la nube. |
| `.github/workflows/compilar.yml` | Instrucciones para la Mac en la nube: probar, compilar, empaquetar y publicar. |
| `.gitignore` | Lista de archivos que nunca se suben (compilaciones, archivos temporales, claves). |
| `diseno/DISENO.md` | Guía de diseño: colores, tipografía, el círculo que respira y cada pantalla. |
| `diseno/configurador.html` | Muestra interactiva de la estética (se abre en el navegador). |
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
6. Abrila: tiene que decir **Hola** y la fecha y hora de la última compilación.

Si la fecha coincide con la de la última compilación en GitHub, estás viendo la versión más nueva.

**Límites de la cuenta gratis de Apple:**
- Las apps vencen a los **7 días**. Abrí SideStore y tocá **Refresh All** antes de que venzan.
- Podés tener hasta **3 apps** instaladas así a la vez (SideStore cuenta como una).
- Instalar una versión nueva reemplaza a la anterior.

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
