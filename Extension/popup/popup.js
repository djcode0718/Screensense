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
      const res = await fetch(`${BRIDGE_URL}/api/status`, {
        method: 'GET',
        headers: { 'Accept': 'application/json' }
      });
      if (res.ok) {
        const data = await res.json().catch(() => ({}));
        statusBadge.textContent = 'App Connected';
        statusBadge.className = 'badge connected';
        return true;
      } else {
        throw new Error(`HTTP ${res.status}`);
      }
    } catch (e) {
      statusBadge.textContent = 'App Offline';
      statusBadge.className = 'badge disconnected';
      return false;
    }
  }

  // Load Active Tab Context Preview via Service Worker
  async function loadActiveTabContext() {
    try {
      chrome.runtime.sendMessage({ action: 'query_active_tab_context' }, (response) => {
        if (chrome.runtime.lastError) {
          console.warn('[ScreenSense Popup] Runtime error querying context:', chrome.runtime.lastError.message);
          visibleCountEl.textContent = 'Unavailable';
          return;
        }

        if (!response || !response.success || !response.context) {
          const err = response?.error || 'No context returned';
          console.warn('[ScreenSense Popup] Context query returned error:', err);
          visibleCountEl.textContent = 'N/A';
          return;
        }

        const ctx = response.context;
        pageTitleEl.textContent = (ctx.viewport?.pageTitle || 'Webpage').substring(0, 24);
        visibleCountEl.textContent = `${ctx.elements?.length || 0} visible`;
        viewportDimEl.textContent = `${ctx.viewport?.width || 0} × ${ctx.viewport?.height || 0}`;

        // Render preview list
        previewList.innerHTML = '';
        if (Array.isArray(ctx.elements)) {
          ctx.elements.slice(0, 10).forEach((el, idx) => {
            const item = document.createElement('div');
            item.className = 'element-item';
            const pct = Math.round((el.visibilityPercentage || 1) * 100);
            item.innerHTML = `
              <span class="element-tag">[${idx + 1}] ${el.type}</span>
              <span class="element-pct">${pct}%</span>
              <div>"${(el.text || '').substring(0, 50)}${(el.text || '').length > 50 ? '...' : ''}"</div>
            `;
            previewList.appendChild(item);
          });
        }
      });
    } catch (e) {
      console.error('[ScreenSense Popup] Error loading active tab context:', e.message);
    }
  }

  // Sync Context Button Handler
  syncBtn.addEventListener('click', async () => {
    syncBtn.textContent = 'Syncing...';

    chrome.runtime.sendMessage({ action: 'sync_active_tab' }, (response) => {
      if (chrome.runtime.lastError) {
        const errMsg = chrome.runtime.lastError.message;
        console.error('[ScreenSense Popup] Sync message error:', errMsg);
        syncBtn.textContent = 'Sync Failed';
        setTimeout(() => { syncBtn.textContent = 'Sync Context to macOS'; }, 2000);
        return;
      }

      if (response && response.success) {
        const count = response.context?.elements?.length || 0;
        console.log(`[ScreenSense Popup] Synced ${count} elements to bridge.`);
        syncBtn.textContent = `✓ Synced ${count} elements!`;
        statusBadge.textContent = 'App Connected';
        statusBadge.className = 'badge connected';
        loadActiveTabContext();
      } else {
        const err = response?.error || 'Unknown bridge error';
        console.error('[ScreenSense Popup] Sync error:', err);
        syncBtn.textContent = 'Sync Error';
      }

      setTimeout(() => {
        syncBtn.textContent = 'Sync Context to macOS';
      }, 2500);
    });
  });

  await checkBridgeStatus();
  await loadActiveTabContext();
});
