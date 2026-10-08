/**
 * ScreenSense Extension Service Worker (Manifest V3)
 * Coordinates automatic and manual context synchronization between active tab and macOS ScreenSense app.
 */

const BRIDGE_URL = 'http://127.0.0.1:41920';

// Inject content scripts into any already-opened tabs on install / startup
async function injectContentScriptsIntoAllTabs() {
  console.log('[SS-TAB-SYNC] injectContentScriptsIntoAllTabs starting...');
  try {
    const tabs = await chrome.tabs.query({ url: ['http://*/*', 'https://*/*', 'file:///*'] });
    console.log(`[SS-TAB-SYNC] Found ${tabs.length} eligible tabs for content script injection`);
    for (const tab of tabs) {
      if (tab.id) {
        await ensureContentScriptInjected(tab.id, tab.url);
      }
    }
  } catch (e) {
    console.debug('[SS-TAB-SYNC] Mass tab injection error:', e.message);
  }
}

chrome.runtime.onInstalled.addListener(() => {
  console.log('[SS-TAB-SYNC] Extension installed/reloaded; initializing content scripts across tabs.');
  injectContentScriptsIntoAllTabs();
});

chrome.runtime.onStartup.addListener(() => {
  console.log('[SS-TAB-SYNC] Extension startup; initializing content scripts across tabs.');
  injectContentScriptsIntoAllTabs();
});

/**
 * Ensures content script is injected in a specific tab
 * @param {number} tabId
 * @param {string} url
 * @returns {Promise<boolean>}
 */
async function ensureContentScriptInjected(tabId, url) {
  if (!url || url.startsWith('chrome://') || url.startsWith('chrome-extension://') || url.startsWith('edge://') || url.startsWith('about:') || url.startsWith('devtools://')) {
    console.log(`[SS-TAB-SYNC] Skipping script injection for internal/restricted tabId=${tabId} url=${url || 'empty'}`);
    return false;
  }
  try {
    console.log(`[SS-TAB-SYNC] Executing script injection on tabId=${tabId} (${url})`);
    await chrome.scripting.executeScript({
      target: { tabId: tabId },
      files: [
        'content/visibility-analyzer.js',
        'content/dom-analyzer.js',
        'content/content.js'
      ]
    });
    console.log(`[SS-TAB-SYNC] Script injection SUCCESS on tabId=${tabId}`);
    return true;
  } catch (e) {
    console.debug(`[SS-TAB-SYNC] Script injection error on tabId=${tabId}:`, e.message);
    return false;
  }
}

/**
 * Pushes structured context payload to macOS ScreenSense Bridge
 * @param {Object} context
 * @param {string} [triggerSource='auto']
 * @returns {Promise<{success: boolean, status?: number, error?: string}>}
 */
async function pushContextToBridge(context, triggerSource = 'auto') {
  if (!context || !Array.isArray(context.elements)) {
    console.warn('[SS-TAB-SYNC] pushContextToBridge invalid context payload structure');
    return { success: false, error: 'Invalid context payload structure' };
  }

  const pageTitle = context.viewport?.pageTitle || 'Webpage';
  const url = context.viewport?.url || 'unknown';
  const tabId = context.metadata?.tab_id || 'unknown';

  console.log(`[SS-TAB-SYNC] POST /api/context dispatching ${context.elements.length} elements from tabId=${tabId} '${pageTitle}' (trigger=${triggerSource})`);

  try {
    const bridgeRes = await fetch(`${BRIDGE_URL}/api/context`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify(context)
    });

    if (bridgeRes.ok) {
      const resData = await bridgeRes.json().catch(() => ({}));
      console.log(`[SS-TAB-SYNC] POST /api/context SUCCESS (HTTP ${bridgeRes.status}) -> ${context.elements.length} elements received by ScreenSense.`, resData);
      return { success: true, status: bridgeRes.status, count: context.elements.length };
    } else {
      const errText = await bridgeRes.text().catch(() => '');
      console.warn(`[SS-TAB-SYNC] POST /api/context FAILED HTTP ${bridgeRes.status}:`, errText);
      return { success: false, status: bridgeRes.status, error: `Bridge returned HTTP ${bridgeRes.status}: ${errText}` };
    }
  } catch (err) {
    console.debug(`[SS-TAB-SYNC] POST /api/context network error (Bridge unreachable):`, err.message);
    return { success: false, error: `Bridge unreachable: ${err.message}` };
  }
}

/**
 * Requests DOM extraction from the given tab with auto-injection fallback
 * @param {chrome.tabs.Tab} tab
 * @returns {Promise<{success: boolean, context?: Object, error?: string}>}
 */
async function extractContextFromTab(tab) {
  if (!tab || !tab.id) {
    return { success: false, error: 'No active tab provided' };
  }
  if (!tab.url || tab.url.startsWith('chrome://') || tab.url.startsWith('chrome-extension://') || tab.url.startsWith('devtools://')) {
    console.log(`[SS-TAB-SYNC] Cannot extract DOM on internal browser page tabId=${tab.id} url=${tab.url || 'unknown'}`);
    return { success: false, error: `Cannot extract DOM on internal browser page (${tab.url || 'unknown'})` };
  }

  console.log(`[SS-TAB-SYNC] extractContextFromTab requesting context from tabId=${tab.id} url=${tab.url}`);

  return new Promise((resolve) => {
    chrome.tabs.sendMessage(tab.id, { action: 'extract_visible_context' }, async (response) => {
      if (chrome.runtime.lastError || !response || !response.success || !response.context) {
        const initialErr = chrome.runtime.lastError?.message || response?.error || 'Extraction failed';
        console.log(`[SS-TAB-SYNC] Initial sendMessage to tabId=${tab.id} result: ${initialErr}`);

        // If receiving end did not exist, inject scripts and retry once
        if (initialErr.includes('Receiving end does not exist') || initialErr.includes('Could not establish connection')) {
          console.log(`[SS-TAB-SYNC] Content script missing in tabId=${tab.id}, injecting dynamically...`);
          const injected = await ensureContentScriptInjected(tab.id, tab.url);
          if (injected) {
            setTimeout(() => {
              chrome.tabs.sendMessage(tab.id, { action: 'extract_visible_context' }, (retryResponse) => {
                if (chrome.runtime.lastError || !retryResponse || !retryResponse.success || !retryResponse.context) {
                  const retryErr = chrome.runtime.lastError?.message || retryResponse?.error || 'Extraction retry failed';
                  console.warn(`[SS-TAB-SYNC] Retry extraction failed on tabId=${tab.id}:`, retryErr);
                  resolve({ success: false, error: `Tab ${tab.id} extraction failed after injection: ${retryErr}` });
                } else {
                  const ctx = enrichContextMetadata(retryResponse.context, tab);
                  console.log(`[SS-TAB-SYNC] Retry extraction SUCCESS on tabId=${tab.id}: ${ctx.elements.length} elements`);
                  resolve({ success: true, context: ctx });
                }
              });
            }, 60);
            return;
          }
        }

        resolve({ success: false, error: `Tab ${tab.id} extraction error: ${initialErr}` });
        return;
      }

      const ctx = enrichContextMetadata(response.context, tab);
      console.log(`[SS-TAB-SYNC] extractContextFromTab SUCCESS on tabId=${tab.id}: ${ctx.elements.length} elements from '${ctx.viewport.pageTitle || 'page'}'`);
      resolve({ success: true, context: ctx });
    });
  });
}

function enrichContextMetadata(context, tab) {
  if (!context) return context;
  if (!context.metadata) context.metadata = {};
  context.metadata.tab_id = String(tab.id || '');
  context.metadata.window_id = String(tab.windowId || '');
  if (!context.viewport.pageTitle && tab.title) {
    context.viewport.pageTitle = tab.title;
  }
  if (!context.viewport.url && tab.url) {
    context.viewport.url = tab.url;
  }
  return context;
}

/**
 * Extracts and pushes context for a specific tab or active tab
 * @param {number} [tabId]
 * @param {string} [triggerSource='auto']
 */
async function syncTabContext(tabId, triggerSource = 'tab_event') {
  try {
    let targetTab = null;
    if (tabId) {
      targetTab = await chrome.tabs.get(tabId).catch(() => null);
    }
    if (!targetTab) {
      const [active] = await chrome.tabs.query({ active: true, currentWindow: true });
      targetTab = active;
    }

    if (!targetTab || !targetTab.id) {
      console.log(`[SS-TAB-SYNC] syncTabContext: No active tab found for trigger=${triggerSource}`);
      return;
    }

    console.log(`[SS-TAB-SYNC] syncTabContext triggering extraction for tabId=${targetTab.id} url=${targetTab.url} (trigger=${triggerSource})`);
    const result = await extractContextFromTab(targetTab);
    if (result.success && result.context) {
      await pushContextToBridge(result.context, triggerSource);
    }
  } catch (err) {
    console.debug(`[SS-TAB-SYNC] syncTabContext error:`, err.message);
  }
}

// 1. Tab Activation (User switches to another tab)
chrome.tabs.onActivated.addListener((activeInfo) => {
  console.log(`[SS-TAB-SYNC] tabs.onActivated tabId=${activeInfo.tabId} windowId=${activeInfo.windowId}`);
  // Immediately sync the newly activated tab
  syncTabContext(activeInfo.tabId, 'tabs.onActivated');
});

// 2. Tab Navigation / Reload / Status Update
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.active) {
    console.log(`[SS-TAB-SYNC] tabs.onUpdated complete on active tabId=${tabId} url=${tab.url}`);
    syncTabContext(tabId, 'tabs.onUpdated');
  }
});

// 3. Window Focus Changed (User switches Chrome windows)
chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId !== chrome.windows.WINDOW_ID_NONE) {
    console.log(`[SS-TAB-SYNC] windows.onFocusChanged windowId=${windowId}`);
    syncTabContext(null, 'windows.onFocusChanged');
  }
});

// 4. Relay requests from content script, popup, or keyboard shortcuts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'auto_sync_context') {
    const senderTabId = sender?.tab?.id || 'unknown';
    const scrollY = message.context?.viewport?.scrollY ?? 0;
    console.log(`[SS-VIEWPORT-SYNC] Service worker received auto_sync_context tabId=${senderTabId} scrollY=${scrollY} elements=${message.context?.elements?.length || 0}`);
    if (message.context) {
      if (sender?.tab) {
        enrichContextMetadata(message.context, sender.tab);
      }
      pushContextToBridge(message.context, `content.auto_sync(tabId=${senderTabId},scrollY=${scrollY})`);
    }
    sendResponse({ success: true });
    return true;
  }

  if (message.action === 'query_active_tab_context' || message.action === 'sync_active_tab') {
    (async () => {
      try {
        const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!activeTab || !activeTab.id) {
          sendResponse({ success: false, error: 'No active tab found' });
          return;
        }

        console.log(`[SS-TAB-SYNC] Popup sync_active_tab on tabId=${activeTab.id} url=${activeTab.url}`);
        const extractRes = await extractContextFromTab(activeTab);
        if (!extractRes.success || !extractRes.context) {
          sendResponse({ success: false, error: extractRes.error || 'Extraction failed' });
          return;
        }

        const bridgeRes = await pushContextToBridge(extractRes.context, 'popup.manual_sync');
        if (bridgeRes.success) {
          sendResponse({ success: true, context: extractRes.context, bridgeStatus: bridgeRes.status });
        } else {
          sendResponse({ success: false, context: extractRes.context, error: bridgeRes.error });
        }
      } catch (error) {
        console.error('[SS-TAB-SYNC] Error in service worker handler:', error);
        sendResponse({ success: false, error: error.message });
      }
    })();
    return true;
  }
});
