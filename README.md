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
| `AppTDAH/AppTDAHApp.swift` | Punto de arranque de la app: abre la pantalla principal. |
| `AppTDAH/ContentView.swift` | La pantalla que ves: "Hola" y la fecha de compilación. |
| `AppTDAH/Textos.swift` | Los textos de la app y cómo se escribe la fecha (separado para poder probarlo). |
| `AppTDAH/BuildInfo.swift` | Guarda la fecha y versión de compilación; la nube lo reescribe en cada compilación. |
| `AppTDAHTests/TextosTests.swift` | Pruebas automáticas que revisan que los textos sean correctos. |
| `project.yml` | Receta del proyecto: XcodeGen la usa para crear el proyecto de Xcode en la nube. |
| `.github/workflows/compilar.yml` | Instrucciones para la Mac en la nube: probar, compilar, empaquetar y publicar. |
| `.gitignore` | Lista de archivos que nunca se suben (compilaciones, archivos temporales, claves). |
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

## Seguridad

Este repositorio es público. No contiene claves, contraseñas ni datos personales, y no debe
contenerlos nunca. La compilación se publica con el permiso automático de GitHub, sin claves guardadas.
