{{flutter_js}}
{{flutter_build_config}}

(async () => {
  // Retire only this app's legacy offline worker/cache; keep logos and presets.
  if ('serviceWorker' in navigator) {
    try {
      const scope = new URL('./', location.href).href;
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.filter(r => r.scope === scope)
        .map(r => r.unregister()));
      if ('caches' in window) {
        await Promise.all(['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']
          .map(name => caches.delete(name)));
      }
      if (navigator.serviceWorker.controller &&
          sessionStorage.getItem('watermark-worker-migrated') !== '1') {
        sessionStorage.setItem('watermark-worker-migrated', '1');
        location.reload();
        return;
      }
    } catch (error) {
      console.warn('Legacy cache cleanup unavailable', error);
    }
  }
  _flutter.loader.load();
})();
