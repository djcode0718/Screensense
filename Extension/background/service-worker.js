/**
 * ScreenSense Extension Service Worker (Manifest V3)
 * Coordinates context extraction between active tab and macOS ScreenSense app.
 */

// Handle extension icon clicks or background queries
chrome.runtime.onInstalled.addListener(() => {
  console.log('[ScreenSense] Extension installed and background worker ready.');
});

// Relay requests from popup / native messaging to content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'query_active_tab_context') {
    (async () => {
      try {
        const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!activeTab || !activeTab.id) {
          sendResponse({ success: false, error: 'No active tab found' });
          return;
        }

        // Send extraction command to content script in active tab
        const response = await chrome.tabs.sendMessage(activeTab.id, {
          action: 'push_context_to_bridge'
        });
        sendResponse(response);
      } catch (error) {
        console.error('[ScreenSense] Error querying active tab:', error);
        sendResponse({ success: false, error: error.message });
      }
    })();
    return true; // Keep message channel open for async response
  }
});
