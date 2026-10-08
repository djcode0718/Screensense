/**
 * ScreenSense Chrome Extension - Popup Controller
 * Manages connection status and synchronization of visible DOM context to macOS app.
 */
document.addEventListener('DOMContentLoaded', async () => {
  const statusBadge = document.getElementById('bridgeStatus');
  const pageTitleEl = document.getElementById('pageTitle');
  const visibleCountEl = document.getElementById('visibleCount');
  const viewportDimEl = document.getElementById('viewportDim');
  const previewList = document.getElementById('previewList');
  const syncBtn = document.getElementById('syncBtn');

  const BRIDGE_URL = 'http://127.0.0.1:41920';

  // Check macOS Bridge Status
  async function checkBridgeStatus() {
    try {
      console.log(`[ScreenSense Popup] Checking bridge status at ${BRIDGE_URL}/api/status...`);
      const res = await fetch(`${BRIDGE_URL}/api/status`, {
        method: 'GET',
        headers: { 'Accept': 'application/json' }
      });
      if (res.ok) {
        const data = await res.json();
        console.log('[ScreenSense Popup] Bridge response:', data);
        statusBadge.textContent = 'App Connected';
        statusBadge.className = 'badge connected';
        return true;
      } else {
        throw new Error(`HTTP ${res.status}`);
      }
    } catch (e) {
      console.warn('[ScreenSense Popup] Bridge unreachable:', e.message);
      statusBadge.textContent = 'App Offline';
      statusBadge.className = 'badge disconnected';
      return false;
    }
  }

  // Load Active Tab Context Preview
  async function loadActiveTabContext() {
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) {
        console.warn('[ScreenSense Popup] No active tab found.');
        return;
      }

      chrome.tabs.sendMessage(tab.id, { action: 'extract_visible_context' }, (response) => {
        if (chrome.runtime.lastError || !response || !response.success || !response.context) {
          console.warn('[ScreenSense Popup] Content script extraction returned:', chrome.runtime.lastError || response);
          visibleCountEl.textContent = 'N/A';
          return;
        }

        const ctx = response.context;
        pageTitleEl.textContent = (ctx.viewport.pageTitle || 'Webpage').substring(0, 24);
        visibleCountEl.textContent = `${ctx.elements.length} visible`;
        viewportDimEl.textContent = `${ctx.viewport.width} × ${ctx.viewport.height}`;

        // Render preview list
        previewList.innerHTML = '';
        ctx.elements.slice(0, 10).forEach((el, idx) => {
          const item = document.createElement('div');
          item.className = 'element-item';
          const pct = Math.round(el.visibilityPercentage * 100);
          item.innerHTML = `
            <span class="element-tag">[${idx + 1}] ${el.type}</span>
            <span class="element-pct">${pct}%</span>
            <div>"${el.text.substring(0, 50)}${el.text.length > 50 ? '...' : ''}"</div>
          `;
          previewList.appendChild(item);
        });
      });
    } catch (e) {
      console.error('[ScreenSense Popup] Error loading active tab context:', e);
    }
  }

  // Sync Context Button Handler
  syncBtn.addEventListener('click', async () => {
    syncBtn.textContent = 'Extracting...';
    console.log('[ScreenSense Popup] Sync initiated by user.');

    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) {
        syncBtn.textContent = 'No Active Tab';
        setTimeout(() => { syncBtn.textContent = 'Sync Context to macOS'; }, 2000);
        return;
      }

      // Step 1: Request visible context extraction from content script
      chrome.tabs.sendMessage(tab.id, { action: 'extract_visible_context' }, async (response) => {
        if (chrome.runtime.lastError || !response || !response.success || !response.context) {
          const errMsg = chrome.runtime.lastError?.message || response?.error || 'Unknown error';
          console.error('[ScreenSense Popup] Extraction failed:', errMsg);
          syncBtn.textContent = 'Extraction Failed';
          setTimeout(() => { syncBtn.textContent = 'Sync Context to macOS'; }, 2000);
          return;
        }

        const context = response.context;
        console.log(`[ScreenSense Popup] Extracted ${context.elements.length} elements from ${context.viewport.pageTitle || 'page'}.`);
        syncBtn.textContent = 'Sending to macOS...';

        // Step 2: Post payload directly from privileged extension context to macOS bridge
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
            const resData = await bridgeRes.json();
            console.log('[ScreenSense Popup] Bridge sync SUCCESS:', resData);
            syncBtn.textContent = `✓ Synced ${context.elements.length} elements!`;
            statusBadge.textContent = 'App Connected';
            statusBadge.className = 'badge connected';
          } else {
            const errText = await bridgeRes.text();
            console.error(`[ScreenSense Popup] Bridge error ${bridgeRes.status}:`, errText);
            syncBtn.textContent = `Bridge Error (${bridgeRes.status})`;
          }
        } catch (fetchError) {
          console.error('[ScreenSense Popup] Failed to connect to ScreenSense bridge:', fetchError);
          syncBtn.textContent = 'Sync Failed (App Offline)';
          statusBadge.textContent = 'App Offline';
          statusBadge.className = 'badge disconnected';
        }

        setTimeout(() => {
          syncBtn.textContent = 'Sync Context to macOS';
        }, 2500);
      });
    } catch (e) {
      console.error('[ScreenSense Popup] Unexpected sync error:', e);
      syncBtn.textContent = 'Sync Error';
      setTimeout(() => { syncBtn.textContent = 'Sync Context to macOS'; }, 2000);
    }
  });

  await checkBridgeStatus();
  await loadActiveTabContext();
});
