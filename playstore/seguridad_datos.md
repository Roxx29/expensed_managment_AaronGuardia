# Monchi — Formulario "Seguridad de los datos" de Google Play

Respuestas para Play Console › Política › Contenido de la app › Seguridad de los datos.
Basado en `PRIVACY.md` y en el código del 2026-10-13. Si cambia lo que la app envía a Firebase, actualiza las dos cosas.

## Recopilación y uso compartido

- **¿Tu app recopila o comparte alguno de los tipos de datos de usuario obligatorios?** Sí.
- **¿Todos los datos se encriptan en tránsito?** Sí (HTTPS con Firebase).
- **¿Ofreces una forma de solicitar que se borren los datos?** Sí: en la app (Más › Copia de seguridad › Eliminar cuenta y datos en la nube) y en https://monchiadmin.nubiksoft.com/borrar-cuenta/
- **¿Compartes datos con terceros?** No. Firebase (Google) actúa como proveedor de servicios, y eso no cuenta como "compartir" para Play.

## Tipos de datos (marca solo estos)

| Categoría de Play | Tipo | ¿Recopilado? | ¿Opcional? | Para qué |
|---|---|---|---|---|
| Información personal | Nombre | Sí | Sí (solo si inicias sesión) | Funciones de la app, Gestión de la cuenta |
| Información personal | Dirección de correo | Sí | Sí | Gestión de la cuenta, Comunicaciones con el desarrollador (reportes) |
| Información personal | ID de usuario | Sí | Sí | Gestión de la cuenta |
| Fotos y videos | Fotos | Sí | Sí (foto de perfil) | Funciones de la app (mostrar tu foto en tus teléfonos) |
| Información financiera | Historial de compras | Sí | Sí (Premium) | Funciones de la app (saber qué plan tienes) |
| Información financiera | Otra información financiera | Sí | Sí | Funciones de la app: copia en la nube y carteras compartidas. **Cifrado de extremo a extremo** (ni el desarrollador ni Google pueden leerlo) |
| Archivos y documentos | Archivos y documentos | Sí | Sí | Copia de seguridad cifrada en la nube |
| Actividad en la app | Interacciones con la app | Sí | Sí (solo con sesión) | Estadísticas (días de uso, contador de funciones; nunca lo que registras) |
| Actividad en la app | Otro contenido generado por el usuario | Sí | Sí | Reportes de problemas (texto que escribes) → Comunicaciones con el desarrollador |
| Información y rendimiento de la app | Registros de fallos | Sí | No | Estadísticas (Crashlytics) |
| Información y rendimiento de la app | Diagnóstico | Sí | No | Estadísticas (modelo y versión de Android en el informe de fallo) |
| Identificadores del dispositivo u otros | — | No | | Crashlytics usa un ID de instalación, no un ID de dispositivo ni de publicidad |

No marques: ubicación, contactos, mensajes, audio, salud, calendario, navegación web, información de pago (Google Play procesa los pagos, Monchi no los ve).

**Datos procesados solo en el teléfono (no cuentan como recopilados):** la cámara para escanear recibos (el OCR va en el teléfono) y la huella o el rostro para el bloqueo.

## Para cada tipo marcado

- **¿Se procesan de forma efímera?** No (quedan guardados hasta que borras la cuenta).
- **¿Es obligatorio o el usuario puede elegir?** Opcional en todos, salvo los registros de fallos y el diagnóstico. Para esos responde "Obligatorio": Crashlytics está siempre activo en Android.

## Prácticas de seguridad (sección final)

- Datos encriptados en tránsito: **Sí**
- Puedes solicitar que se borren los datos: **Sí**
- Revisión de seguridad independiente: **No**
- Cumple la Política de Familias: no aplica (público 18+)
