/**
 * ScreenSense Content Script
 * Listens for context extraction requests and dispatches viewport DOM analysis.
 */
(() => {
  // Listen for messages from popup or background script
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'extract_visible_context') {
      try {
        const context = window.ScreenSenseDOMAnalyzer.extractVisibleContext();
        sendResponse({ success: true, context });
      } catch (error) {
        console.error('[ScreenSense] Extraction error:', error);
        sendResponse({ success: false, error: error.message });
      }
      return true;
    }

    if (message.action === 'push_context_to_bridge') {
      (async () => {
        try {
          const context = window.ScreenSenseDOMAnalyzer.extractVisibleContext();
          const bridgeResponse = await fetch('http://127.0.0.1:41920/api/context', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(context)
          });

          if (bridgeResponse.ok) {
            const data = await bridgeResponse.json();
            sendResponse({ success: true, bridgeResult: data, context });
          } else {
            sendResponse({ success: false, error: `Bridge returned status ${bridgeResponse.status}` });
          }
        } catch (error) {
          sendResponse({ success: false, error: error.message });
        }
      })();
      return true;
    }
  });

  // Optional: Auto-sync context on scroll/resize with debounce (disabled by default or on-demand)
  let syncTimeout = null;
  const syncToBridgeOnScroll = () => {
    if (syncTimeout) clearTimeout(syncTimeout);
    syncTimeout = setTimeout(async () => {
      try {
        const context = window.ScreenSenseDOMAnalyzer.extractVisibleContext();
        await fetch('http://127.0.0.1:41920/api/context', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(context)
        });
      } catch (e) {
        // macOS app might not be running, fail silently
      }
    }, 400);
  };

  window.addEventListener('scroll', syncToBridgeOnScroll, { passive: true });
  window.addEventListener('resize', syncToBridgeOnScroll, { passive: true });
})();
