# Reglas permanentes del proyecto AppTDAH

Este repositorio es **PÚBLICO**. Cualquiera puede leer todo lo que se sube.

1. Nunca escribir claves, tokens, contraseñas, certificados ni perfiles de aprovisionamiento
   en el código ni en ningún archivo del repositorio.
2. Nunca escribir datos personales (nombres reales, emails, teléfonos, Apple ID, direcciones)
   en el código, en los commits ni en la documentación.
3. Si algún día hace falta un secreto, va en *GitHub → Settings → Secrets and variables → Actions*
   y el workflow lo lee con `${{ secrets.NOMBRE }}`. Nunca se imprime en el registro.
4. Los commits usan el email privado `...@users.noreply.github.com`, no un email real.
5. El proyecto de Xcode (`AppTDAH.xcodeproj`) no se sube: se genera con XcodeGen desde `project.yml`.
6. El dueño del proyecto es diseñador, no programador: explicar todo en español, en pocas líneas
   y sin jerga.
7. La compilación usa siempre el runner `macos-latest` estándar (gratis en repos públicos).
   Nunca usar runners "xlarge" ni otros pagos.
