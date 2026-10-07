# Monchi — Política de privacidad / Privacy policy

Última actualización / Last updated: 2026-10-04

## Español

Monchi es una app para llevar tus gastos. Está hecha para que tus datos sean solo tuyos.

**Datos en tu teléfono.** Tus movimientos, presupuestos, metas, categorías y ajustes se guardan solo en tu teléfono. Monchi no tiene servidores propios, no muestra anuncios, no usa analítica y no vende ni comparte datos.

**Copia en la nube (opcional).** Si inicias sesión con tu correo o con Google (copia en la nube, códigos o Premium regalado):
- Guardamos tu correo, tu nombre de Google (si entras con Google) y un identificador de cuenta en Firebase (Google) para saber qué copia es tuya y qué Premium tienes. Si creas una cuenta con correo, Firebase guarda tu contraseña protegida (nunca la vemos). También guardamos la fecha en que abriste la app por última vez, su versión, si pagas Premium y qué plan (mensual, anual o de por vida), cuántas veces abriste la app, en qué días de los últimos 60 la usaste y cuántas veces usaste cada función (por ejemplo "Estadísticas" o "Escanear recibo"; solo el nombre de la función y un número, nunca lo que registras), para atender soporte y regalos de Premium y para ver estadísticas generales de uso. Si no inicias sesión, no se guarda nada de esto.
- Si la app se cierra por un error, en Android se envía un informe técnico a Firebase Crashlytics (Google): el error, la parte del código donde ocurrió, el modelo de teléfono y la versión de Android y de la app. No incluye tu correo, tu nombre ni tus movimientos. Sirve solo para corregir fallos.
- Tu copia se cifra en tu teléfono con una contraseña que solo tú conoces (AES-256-GCM) antes de subirla a Firebase Firestore (Google). Nadie más puede leerla, ni siquiera el desarrollador.
- Si activas la sincronización automática (Premium), esa contraseña se guarda solo en el almacenamiento seguro de tu teléfono para cifrar y descifrar la copia. Nunca se sube. Cada teléfono con la misma cuenta descarga la copia cifrada, la combina con sus datos y la vuelve a subir cifrada.
- Los datos viajan cifrados (HTTPS) y se guardan en los servidores de Google Cloud.

**Carteras compartidas (opcional).** Si creas una cartera (negocio, familia) o te unes a una con un código de invitación, sus movimientos se cifran en los teléfonos con una clave propia de la cartera (AES-256-GCM) antes de subirlos a Firebase Firestore. Esa clave viaja dentro del código de invitación que tú compartes (válido 7 días) y dentro de tus copias de seguridad cifradas con tu contraseña (nube y sincronización); las copias locales sin cifrar no la incluyen. Ni Monchi ni Google pueden leer los movimientos. Ten en cuenta que los movimientos de las carteras también se guardan en tus copias de seguridad, como el resto de tus datos. Para mostrar quién registró cada movimiento, tu nombre y una foto pequeña de tu perfil se guardan también cifrados con esa clave, y solo los ven los miembros de la cartera. Firebase guarda además el identificador de tu cuenta como miembro. Al salir de la cartera (o al eliminar tu cuenta) se borra tu registro de miembro; los movimientos que registraste siguen en la cartera para los demás, y el identificador de tu cuenta puede quedar como creador de la cartera o de una invitación.

**Carpeta Documentos.** Cada copia de seguridad local también se guarda en Documentos › backupmonchi de tu teléfono, sin cifrar, para que no se pierda si desinstalas la app. Solo tú y las apps a las que des acceso a tus archivos pueden verla.

**Copia de seguridad de Android.** Si tienes activada la copia de seguridad de tu cuenta de Google en Android, el sistema guarda ahí las copias de seguridad locales de Monchi (no la base de datos, ni tu PIN, ni tus ajustes), para recuperarlas si reinstalas la app o cambias de teléfono. Android las cifra con el bloqueo de pantalla de tu teléfono. Puedes desactivarlo en Ajustes de Android › Google › Copia de seguridad.

**Avisos.** Al abrir la app, Monchi consulta en Firebase si hay un anuncio (novedades, avisos). Esa consulta no envía tus datos.

**Compras.** Las suscripciones y la compra de por vida se procesan en Google Play. Monchi no ve ni guarda tus datos de pago.

**Permisos.** Cámara (solo para escanear recibos, la lectura se hace en el teléfono), notificaciones (recordatorios) y huella/rostro (bloqueo de la app). Ninguno envía datos fuera del teléfono.

**Eliminar tu cuenta y tus datos.** En la app: Más › Copia de seguridad › *Eliminar cuenta y datos en la nube*. Borra tu copia y tu cuenta al instante. Si ya no tienes la app, escribe a **aguardia280@gmail.com** desde el correo de tu cuenta y la borramos en un máximo de 30 días. Los datos de tu teléfono se borran al desinstalar la app.

**Menores.** Monchi no está dirigida a menores de 13 años.

**Contacto:** aguardia280@gmail.com

## English

Monchi is an expense tracker built so your data stays yours.

**Data on your phone.** Transactions, budgets, goals, categories and settings are stored only on your phone. Monchi has no servers of its own, no ads, no analytics, and never sells or shares data.

**Cloud backup (optional).** If you sign in with your e-mail or with Google (cloud backup, codes or gifted Premium):
- Your e-mail, Google name (when you use Google) and an account id are stored in Firebase (Google) to know which backup and which Premium are yours. For e-mail accounts Firebase keeps your password hashed (we never see it). We also store when you last opened the app, its version and whether you pay for Premium, for support and Premium gifts.
- Your backup is encrypted on your phone with a passphrase only you know (AES-256-GCM) before it is uploaded to Firebase Firestore (Google). Nobody else can read it, not even the developer.
- If you turn on automatic sync (Premium), that passphrase is kept only in your phone's secure storage to encrypt and decrypt the backup. It is never uploaded. Each phone signed in to the same account downloads the encrypted copy, merges it with its data and uploads it encrypted again.
- Data is sent over HTTPS and stored on Google Cloud servers.

**Shared wallets (optional).** If you create a wallet (business, family) or join one with an invite code, its entries are encrypted on the phones with the wallet's own key (AES-256-GCM) before they are uploaded to Firebase Firestore. That key travels inside the invite code you share (valid for 7 days) and inside your passphrase-encrypted backups (cloud backup and sync); unencrypted local backups don't include it. Neither Monchi nor Google can read the entries. Note that shared-wallet entries are also included in your backups, like the rest of your data. To show who recorded each entry, your name and a small profile photo are stored too, encrypted with that key, and only the wallet's members see them. Firebase also stores your account id as a member. Leaving the wallet (or deleting your account) removes your member record; the entries you recorded stay in the wallet for the others, and your account id may remain as the creator of the wallet or of an invitation.

**Documents folder.** Each local backup is also saved, unencrypted, in Documents › backupmonchi on your phone so it survives uninstalling the app. Only you and apps you give file access can see it.

**Android backup.** If your Google account backup is on in Android, the system keeps Monchi's local backup files there (not the database, your PIN or settings) so you get them back after reinstalling or on a new phone. Android encrypts them with your phone's screen lock. You can turn it off in Android Settings › Google › Backup.

**Announcements.** When the app opens it checks Firebase for an announcement (news, notices). That request sends none of your data.

**Purchases.** Subscriptions and the lifetime purchase are handled by Google Play. Monchi never sees or stores payment details.

**Permissions.** Camera (receipt scanning, processed on the phone), notifications (reminders) and fingerprint/face (app lock). None of them send data off the phone.

**Delete your account and data.** In the app: More › Backup & restore › *Delete account and cloud data*. It deletes your backup and account immediately. If you no longer have the app, e-mail **aguardia280@gmail.com** from your account's address and we delete it within 30 days. Data on your phone is removed when you uninstall the app.

**Children.** Monchi is not directed to children under 13.

**Contact:** aguardia280@gmail.com
