/**
 * ScreenSense Extension Service Worker (Manifest V3)
 * Coordinates context extraction between active tab and macOS ScreenSense app.
 */

const BRIDGE_URL = 'http://127.0.0.1:41920';

chrome.runtime.onInstalled.addListener(() => {
  console.log('[ScreenSense SW] Extension installed and background worker active.');
});

// Relay requests from popup or keyboard shortcuts to active tab and forward to bridge
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'query_active_tab_context' || message.action === 'sync_active_tab') {
    (async () => {
      try {
        const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!activeTab || !activeTab.id) {
          sendResponse({ success: false, error: 'No active tab found' });
          return;
        }

        // Send extraction command to content script in active tab
        chrome.tabs.sendMessage(activeTab.id, { action: 'extract_visible_context' }, async (response) => {
          if (chrome.runtime.lastError || !response || !response.success || !response.context) {
            const err = chrome.runtime.lastError?.message || response?.error || 'Extraction failed';
            console.error('[ScreenSense SW] Tab extraction error:', err);
            sendResponse({ success: false, error: err });
            return;
          }

          const context = response.context;
          console.log(`[ScreenSense SW] Posting ${context.elements.length} elements to ${BRIDGE_URL}/api/context...`);

          try {
            const bridgeRes = await fetch(`${BRIDGE_URL}/api/context`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(context)
            });

            if (bridgeRes.ok) {
              const data = await bridgeRes.json();
              console.log('[ScreenSense SW] Bridge successfully updated:', data);
              sendResponse({ success: true, bridgeResult: data, context });
            } else {
              sendResponse({ success: false, error: `Bridge returned HTTP ${bridgeRes.status}` });
            }
          } catch (fetchErr) {
            console.error('[ScreenSense SW] Fetch error connecting to bridge:', fetchErr);
            sendResponse({ success: false, error: fetchErr.message });
          }
        });
      } catch (error) {
        console.error('[ScreenSense SW] Error in service worker handler:', error);
        sendResponse({ success: false, error: error.message });
      }
    })();
    return true; // Keep message channel open for async response
  }
});
