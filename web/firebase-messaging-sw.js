/* RimbaKawal FCM web background service worker.
 * Values are injected during the production GitHub Actions build.
 */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

const config = {
  apiKey: '__FIREBASE_API_KEY__',
  projectId: '__FIREBASE_PROJECT_ID__',
  messagingSenderId: '__FIREBASE_MESSAGING_SENDER_ID__',
  appId: '__FIREBASE_WEB_APP_ID__',
};

if (Object.values(config).every((value) => value && !value.startsWith('__'))) {
  firebase.initializeApp(config);
  const messaging = firebase.messaging();
  messaging.onBackgroundMessage((payload) => {
    console.debug('[RimbaKawal] background push', payload?.data?.kind || 'general');
  });
}
