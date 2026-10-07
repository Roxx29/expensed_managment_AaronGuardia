// Firebase › Configuración del proyecto › Tus apps › app Web "Monchi Admin" ›
// "Configuración del SDK" › Config. Pega aquí apiKey y appId (son públicos:
// la seguridad la ponen las reglas de firebase/firestore.rules).
export const firebaseConfig = {
  apiKey: 'AIzaSyATIByjkh95wygZQ6P7zd9sVPNbpmfnEU4',
  authDomain: 'monchi-fb5e9.firebaseapp.com',
  projectId: 'monchi-fb5e9',
  storageBucket: 'monchi-fb5e9.firebasestorage.app',
  appId: '1:699143520703:web:79d63fe66d48ad3059a10a',
};

// Prices in Play Console (USD), only for the revenue estimate in Resumen.
// Change them here if you change them in Google Play.
export const prices = { monthly: 1.99, yearly: 14.99, lifetime: 29.99 };
