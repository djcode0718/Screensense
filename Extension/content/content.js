/**
 * ScreenSense Content Script
 * Listens for context extraction requests and automatically synchronizes
 * visible DOM context to the background worker on page load, scroll, mutation,
 * tab visibility change, and window focus.
 */
(() => {
  if (window.__SCREENSENSE_CONTENT_INJECTED__) {
    console.log('[SS-TAB-SYNC] Content script already injected on:', window.location.href);
    if (window.__SCREENSENSE_AUTO_SYNC__) {
      window.__SCREENSENSE_AUTO_SYNC__(true);
    }
    return;
  }
  window.__SCREENSENSE_CONTENT_INJECTED__ = true;

  console.log('[SS-TAB-SYNC] Content script initialized on:', window.location.href);

  let syncDebounceTimer = null;
  let lastExtractedHash = '';

  function computeContextHash(context) {
    if (!context || !context.elements) return '';
    const vp = context.viewport;
    const vpHash = vp ? `vp:${Math.round(vp.scrollX)}:${Math.round(vp.scrollY)}:${Math.round(vp.width)}:${Math.round(vp.height)}` : '';
    const elHash = context.elements.map(e => `${e.type}:${e.text.slice(0, 30)}:${Math.round(e.bounds.x)}:${Math.round(e.bounds.y)}:${Math.round(e.bounds.width)}:${Math.round(e.bounds.height)}`).join('|');
    return `${vpHash}#${context.elements.length}#${elHash}`;
  }

  /**
   * Synchronizes visible DOM context to background service worker
   * @param {boolean} [immediate=false] - Whether to bypass debounce delay (for tab activation / focus)
   */
  function autoSyncContext(immediate = false) {
    if (syncDebounceTimer) {
      clearTimeout(syncDebounceTimer);
      syncDebounceTimer = null;
    }

    const currentScrollY = Math.round(window.scrollY);
    console.log(`[SS-VIEWPORT-SYNC] debounce scheduled (immediate=${immediate}) scrollY=${currentScrollY}`);

    const performSync = () => {
      try {
        if (!window.ScreenSenseDOMAnalyzer) {
          console.warn('[SS-TAB-SYNC] ScreenSenseDOMAnalyzer not found on window');
          return;
        }

        console.log(`[SS-VIEWPORT-SYNC] extraction started scrollY=${Math.round(window.scrollY)}`);
        const context = window.ScreenSenseDOMAnalyzer.extractVisibleContext();
        const hash = computeContextHash(context);

        const isChanged = (hash !== lastExtractedHash);
        console.log(`[SS-VIEWPORT-SYNC] extraction complete visibleElements=${context.elements.length} hash=${hash.slice(0, 32)}... changed=${isChanged}`);

        // Allow sync if hash changed OR if immediate sync requested (tab switch)
        if (!immediate && !isChanged && context.elements.length > 0) {
          console.log('[SS-VIEWPORT-SYNC] context unchanged -> skipping POST');
          return; // No meaningful change
        }
        lastExtractedHash = hash;

        console.log(`[SS-VIEWPORT-SYNC] context changed -> POST scrollY=${context.viewport?.scrollY} elements=${context.elements.length}`);

        // Send to background service worker for bridge forwarding
        chrome.runtime.sendMessage({
          action: 'auto_sync_context',
          context: context,
          url: window.location.href,
          title: document.title
        }, (response) => {
          if (chrome.runtime.lastError) {
            console.debug('[SS-VIEWPORT-SYNC] POST failed:', chrome.runtime.lastError.message);
          } else {
            console.log(`[SS-VIEWPORT-SYNC] POST success elements=${context.elements.length}`);
          }
        });
      } catch (err) {
        console.debug('[SS-VIEWPORT-SYNC] Auto-sync error:', err.message);
      }
    };

    if (immediate) {
      performSync();
    } else {
      syncDebounceTimer = setTimeout(performSync, 250);
    }
  }

  window.__SCREENSENSE_AUTO_SYNC__ = autoSyncContext;

  // 1. Initial sync on load
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(() => autoSyncContext(true), 50);
  } else {
    window.addEventListener('DOMContentLoaded', () => setTimeout(() => autoSyncContext(true), 50));
  }
  window.addEventListener('load', () => setTimeout(() => autoSyncContext(true), 100));

  // 2. Immediate sync on tab visibility change (User switches to this tab)
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      console.log('[SS-TAB-SYNC] document visibilityState became VISIBLE on:', window.location.href);
      autoSyncContext(true);
    }
  });

  // 3. Immediate sync on window focus
  window.addEventListener('focus', () => {
    console.log('[SS-TAB-SYNC] window received FOCUS on:', window.location.href);
    autoSyncContext(true);
  });

  // 4. Sync on user scroll / resize (debounced with capture: true for nested scroll containers)
  window.addEventListener('scroll', () => {
    console.log(`[SS-VIEWPORT-SYNC] scroll detected scrollY=${Math.round(window.scrollY)}`);
    autoSyncContext(false);
  }, { passive: true, capture: true });

  window.addEventListener('resize', () => {
    console.log(`[SS-VIEWPORT-SYNC] resize detected width=${window.innerWidth} height=${window.innerHeight}`);
    autoSyncContext(false);
  }, { passive: true });

  // 5. Lightweight passive tracking of last pointer position (zero-cost, no extraction triggered)
  window.addEventListener('mousemove', (e) => {
    window.__SCREENSENSE_LAST_POINTER__ = {
      x: Math.round(e.clientX),
      y: Math.round(e.clientY)
    };
  }, { passive: true });

  // 6. Sync on DOM mutations (debounced)
  const observer = new MutationObserver((mutations) => {
    let hasRelevantChanges = false;
    for (const m of mutations) {
      if (m.type === 'childList' || (m.type === 'attributes' && (m.attributeName === 'style' || m.attributeName === 'class'))) {
        hasRelevantChanges = true;
        break;
      }
    }
    if (hasRelevantChanges) {
      autoSyncContext(false);
    }
  });

  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true, attributes: true });
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true, attributes: true });
      }
    });
  }

  // 6. Explicit extraction and Live Query requests from service worker or popup
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    const reqId = message.requestId || 'unknown';

    if (message.action === 'extract_visible_context' || message.action === 'live_query_dom') {
      console.log(`[SS-LIVEQUERY] Content script received requestId=${reqId} action=${message.action}`);
      try {
        if (!window.ScreenSenseDOMAnalyzer) {
          throw new Error('ScreenSenseDOMAnalyzer not loaded in page context');
        }
        const context = window.ScreenSenseDOMAnalyzer.extractVisibleContext();
        console.log(`[SS-LIVEQUERY] DOM target resolved requestId=${reqId} (elements=${context.elements.length})`);
        sendResponse({ success: true, context, domResult: context });
      } catch (error) {
        console.error(`[SS-LIVEQUERY] ${message.action} error requestId=${reqId}:`, error);
        sendResponse({ success: false, error: error.message });
      }
      return true;
    }

    if (message.action === 'live_query_pointer') {
      console.log(`[SS-LIVEQUERY] Content script received requestId=${reqId} action=live_query_pointer`);
      try {
        if (!window.ScreenSenseDOMAnalyzer) {
          throw new Error('ScreenSenseDOMAnalyzer not loaded in page context');
        }
        const lastPointer = window.__SCREENSENSE_LAST_POINTER__;
        let x = lastPointer?.x;
        let y = lastPointer?.y;

        // If coordinates provided in message parameters, prefer them
        if (typeof message.parameters?.x === 'number') x = message.parameters.x;
        if (typeof message.parameters?.y === 'number') y = message.parameters.y;

        if (typeof x !== 'number' || typeof y !== 'number') {
          // Default to center of viewport if pointer coordinates never recorded
          x = Math.round(window.innerWidth / 2);
          y = Math.round(window.innerHeight / 2);
        }

        console.log(`[SS-LIVEQUERY] Pointer coordinates x=${x} y=${y}`);

        const pointerResult = window.ScreenSenseDOMAnalyzer.getElementAtPoint(x, y);
        console.log(`[SS-LIVEQUERY] DOM target resolved requestId=${reqId} status=${pointerResult.status}`);
        sendResponse({
          success: true,
          pointerResult: pointerResult
        });
      } catch (error) {
        console.error(`[SS-LIVEQUERY] live_query_pointer error requestId=${reqId}:`, error);
        sendResponse({ success: false, error: error.message });
      }
      return true;
    }

    if (message.action === 'live_query_selection') {
      console.log(`[SS-LIVEQUERY] Content script received requestId=${reqId} action=live_query_selection`);
      try {
        if (!window.ScreenSenseDOMAnalyzer) {
          throw new Error('ScreenSenseDOMAnalyzer not loaded in page context');
        }
        const selectionResult = window.ScreenSenseDOMAnalyzer.getActiveSelectionDetails();
        console.log(`[SS-LIVEQUERY] DOM target resolved requestId=${reqId} status=${selectionResult.status} textLen=${selectionResult.text?.length || 0}`);
        sendResponse({
          success: true,
          selectionResult: selectionResult
        });
      } catch (error) {
        console.error(`[SS-LIVEQUERY] live_query_selection error requestId=${reqId}:`, error);
        sendResponse({ success: false, error: error.message });
      }
      return true;
    }

    if (message.action === 'live_query_tab') {
      console.log(`[SS-LIVEQUERY] Content script received requestId=${reqId} action=live_query_tab`);
      const viewportInfo = {
        width: window.innerWidth || document.documentElement.clientWidth,
        height: window.innerHeight || document.documentElement.clientHeight,
        scrollX: Math.round(window.scrollX * 10) / 10,
        scrollY: Math.round(window.scrollY * 10) / 10,
        devicePixelRatio: window.devicePixelRatio || 1.0,
        pageTitle: document.title || null,
        url: window.location.href || null
      };
      sendResponse({
        success: true,
        viewport: viewportInfo,
        documentReadyState: document.readyState
      });
      return true;
    }
  });
})();
