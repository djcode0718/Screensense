/**
 * ScreenSense Content Script
 * Listens for context extraction requests and dispatches viewport DOM analysis.
 */
(() => {
  console.log('[ScreenSense Content] Injected on:', window.location.href);

  // Listen for messages from popup or background script
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'extract_visible_context') {
      try {
        if (!window.ScreenSenseDOMAnalyzer) {
          throw new Error('ScreenSenseDOMAnalyzer not loaded in page context');
        }
        const context = window.ScreenSenseDOMAnalyzer.extractVisibleContext();
        console.log(`[ScreenSense Content] Extracted ${context.elements.length} visible elements.`);
        sendResponse({ success: true, context });
      } catch (error) {
        console.error('[ScreenSense Content] Extraction error:', error);
        sendResponse({ success: false, error: error.message });
      }
      return true;
    }
  });
})();
