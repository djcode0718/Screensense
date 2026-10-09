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

// 5. Command-Time Live Query Bidirectional Channel
let isQueryLoopRunning = false;

async function postQueryResponse(responsePayload) {
  try {
    const res = await fetch(`${BRIDGE_URL}/api/query/response`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify(responsePayload)
    });
    console.log(`[SS-LIVEQUERY] POST /api/query/response for reqId=${responsePayload.requestId} -> HTTP ${res.status}`);
  } catch (err) {
    console.debug(`[SS-LIVEQUERY] Failed to post query response for reqId=${responsePayload.requestId}:`, err.message);
  }
}

async function handleLiveQuery(queryRequest) {
  const reqId = queryRequest.requestId;
  const qType = queryRequest.type;
  console.log(`[SS-LIVEQUERY] Service worker received requestId=${reqId} type=${qType}`);

  // 1. Identify currently active tab across focused or fallback windows
  let activeTab = null;
  try {
    const tabsInLastFocused = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (tabsInLastFocused && tabsInLastFocused.length > 0) {
      activeTab = tabsInLastFocused[0];
    }
  } catch (e) {
    // Ignore and fallback
  }

  if (!activeTab || !activeTab.id) {
    try {
      const tabsInCurrent = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tabsInCurrent && tabsInCurrent.length > 0) {
        activeTab = tabsInCurrent[0];
      }
    } catch (e) {
      // Ignore
    }
  }

  if (!activeTab || !activeTab.id) {
    try {
      const allActive = await chrome.tabs.query({ active: true });
      if (allActive && allActive.length > 0) {
        activeTab = allActive[0];
      }
    } catch (e) {
      // Ignore
    }
  }

  if (!activeTab || !activeTab.id) {
    console.warn(`[SS-LIVEQUERY] No active tab found for reqId=${reqId}`);
    await postQueryResponse({
      requestId: reqId,
      success: false,
      status: 'NO_ACTIVE_CHROME_TAB',
      error: 'No active Chrome tab found'
    });
    return;
  }

  console.log(`[SS-LIVEQUERY] Active tab resolved tabId=${activeTab.id} url=${activeTab.url || 'none'} title="${activeTab.title || ''}"`);

  if (!activeTab.url || activeTab.url.startsWith('chrome://') || activeTab.url.startsWith('chrome-extension://') || activeTab.url.startsWith('devtools://')) {
    console.warn(`[SS-LIVEQUERY] Active tab is restricted page (${activeTab.url}) for reqId=${reqId}`);
    await postQueryResponse({
      requestId: reqId,
      success: false,
      status: 'NO_ACTIVE_CHROME_TAB',
      error: `Cannot query restricted browser tab (${activeTab.url})`,
      tabId: String(activeTab.id),
      url: activeTab.url,
      pageTitle: activeTab.title
    });
    return;
  }

  // 2. Map query type to action
  let actionName = 'live_query_dom';
  if (qType === 'active_pointer') actionName = 'live_query_pointer';
  else if (qType === 'active_selection') actionName = 'live_query_selection';
  else if (qType === 'active_tab') actionName = 'live_query_tab';
  else if (qType === 'active_dom') actionName = 'live_query_dom';

  console.log(`[SS-LIVEQUERY] Sending content message requestId=${reqId} action=${actionName}`);

  // 3. Dispatch to content script of active tab with injection fallback
  const sendQueryMessage = () => new Promise((resolve) => {
    chrome.tabs.sendMessage(activeTab.id, { action: actionName, requestId: reqId, parameters: queryRequest.parameters }, async (response) => {
      if (chrome.runtime.lastError || !response) {
        const errMsg = chrome.runtime.lastError?.message || 'No response from content script';
        console.warn(`[SS-LIVEQUERY] content script unavailable on tabId=${activeTab.id}: ${errMsg}`);
        if (errMsg.includes('Receiving end does not exist') || errMsg.includes('Could not establish connection')) {
          console.log(`[SS-LIVEQUERY] Content script missing in active tab ${activeTab.id}, injecting dynamically and retrying query...`);
          const injected = await ensureContentScriptInjected(activeTab.id, activeTab.url);
          if (injected) {
            setTimeout(() => {
              chrome.tabs.sendMessage(activeTab.id, { action: actionName, requestId: reqId, parameters: queryRequest.parameters }, (retryResponse) => {
                if (chrome.runtime.lastError || !retryResponse) {
                  const retryErr = chrome.runtime.lastError?.message || 'Retry failed';
                  console.warn(`[SS-LIVEQUERY] Retry failed on tabId=${activeTab.id}: ${retryErr}`);
                  resolve({ success: false, status: 'CONTENT_SCRIPT_UNAVAILABLE', error: retryErr });
                } else {
                  console.log(`[SS-LIVEQUERY] Retry succeeded on tabId=${activeTab.id} for reqId=${reqId}`);
                  resolve(retryResponse);
                }
              });
            }, 60);
            return;
          }
        }
        resolve({ success: false, status: 'CONTENT_SCRIPT_UNAVAILABLE', error: errMsg });
        return;
      }
      resolve(response);
    });
  });

  const tabResponse = await sendQueryMessage();
  console.log(`[SS-LIVEQUERY] Content response received requestId=${reqId} status=${tabResponse.status || (tabResponse.success !== false ? 'OK' : 'FAILED')}`);

  // 4. Verify tab didn't switch during query execution
  try {
    const [currentActive] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (currentActive && currentActive.id !== activeTab.id) {
      console.warn(`[SS-LIVEQUERY] Tab changed during query execution (was ${activeTab.id}, now ${currentActive.id})`);
      await postQueryResponse({
        requestId: reqId,
        success: false,
        status: 'TAB_CHANGED_DURING_QUERY',
        error: 'Active tab changed during query execution',
        tabId: String(currentActive.id),
        url: currentActive.url,
        pageTitle: currentActive.title
      });
      return;
    }
  } catch (e) {
    // Ignore
  }

  // 5. Package live query response
  const queryResultPayload = {
    requestId: reqId,
    success: tabResponse.success !== false,
    status: tabResponse.status || (tabResponse.success !== false ? 'OK' : 'LIVE_QUERY_FAILED'),
    error: tabResponse.error || null,
    tabId: String(activeTab.id),
    url: activeTab.url || '',
    pageTitle: activeTab.title || '',
    viewport: tabResponse.viewport || tabResponse.context?.viewport || tabResponse.domResult?.viewport || null,
    pointerResult: tabResponse.pointerResult || null,
    selectionResult: tabResponse.selectionResult || null,
    domResult: tabResponse.domResult || tabResponse.context || null,
    timestamp: new Date().toISOString()
  };

  console.log(`[SS-LIVEQUERY] Sending response requestId=${reqId} status=${queryResultPayload.status}`);
  await postQueryResponse(queryResultPayload);
}

async function listenForLiveQueries() {
  if (isQueryLoopRunning) return;
  isQueryLoopRunning = true;
  console.log('[SS-LIVEQUERY] service worker initialized');
  console.log('[SS-LIVEQUERY] starting pending-query listener');

  while (isQueryLoopRunning) {
    console.log('[SS-LIVEQUERY] waiting for pending query');
    try {
      const res = await fetch(`${BRIDGE_URL}/api/query/pending`, {
        method: 'GET',
        headers: { 'Accept': 'application/json' }
      });

      if (res.status === 200) {
        const queryRequest = await res.json();
        if (queryRequest && queryRequest.requestId) {
          console.log(`[SS-LIVEQUERY] received pending request requestId=${queryRequest.requestId}`);
          handleLiveQuery(queryRequest).catch((err) => {
            console.error(`[SS-LIVEQUERY] Error processing query requestId=${queryRequest.requestId}:`, err);
          });
        }
      } else if (res.status === 204) {
        console.log('[SS-LIVEQUERY] Pending query keep-alive cycle completed (204 No Content), reconnecting...');
      } else {
        console.warn(`[SS-LIVEQUERY] Bridge returned HTTP ${res.status}, retrying in 1s...`);
        await new Promise(r => setTimeout(r, 1000));
      }
    } catch (err) {
      console.warn('[SS-LIVEQUERY] Pending query network error (bridge unreachable?):', err.message);
      await new Promise(r => setTimeout(r, 1500));
    }
  }
}

// Hook into all lifecycle and wake-up events to guarantee listener is running
chrome.runtime.onInstalled.addListener(() => {
  console.log('[SS-LIVEQUERY] runtime.onInstalled triggered; ensuring listener is running');
  listenForLiveQueries();
});

chrome.runtime.onStartup.addListener(() => {
  console.log('[SS-LIVEQUERY] runtime.onStartup triggered; ensuring listener is running');
  listenForLiveQueries();
});

chrome.tabs.onActivated.addListener(() => {
  listenForLiveQueries();
});

chrome.windows.onFocusChanged.addListener(() => {
  listenForLiveQueries();
});

// Start live query listener loop immediately on load
listenForLiveQueries();

