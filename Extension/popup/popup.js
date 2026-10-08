/**
 * Popup Script for ScreenSense Chrome Extension
 */
document.addEventListener('DOMContentLoaded', async () => {
  const statusBadge = document.getElementById('bridgeStatus');
  const pageTitleEl = document.getElementById('pageTitle');
  const visibleCountEl = document.getElementById('visibleCount');
  const viewportDimEl = document.getElementById('viewportDim');
  const previewList = document.getElementById('previewList');
  const syncBtn = document.getElementById('syncBtn');

  // Check macOS Bridge Status
  async function checkBridgeStatus() {
    try {
      const res = await fetch('http://127.0.0.1:41920/api/status', { method: 'GET' });
      if (res.ok) {
        statusBadge.textContent = 'App Connected';
        statusBadge.className = 'badge connected';
      } else {
        throw new Error('Not OK');
      }
    } catch (e) {
      statusBadge.textContent = 'App Offline';
      statusBadge.className = 'badge disconnected';
    }
  }

  // Load Active Tab Context
  async function loadActiveTabContext() {
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) return;

      chrome.tabs.sendMessage(tab.id, { action: 'extract_visible_context' }, (response) => {
        if (chrome.runtime.lastError || !response || !response.success) {
          visibleCountEl.textContent = 'N/A';
          return;
        }

        const ctx = response.context;
        pageTitleEl.textContent = (ctx.viewport.pageTitle || 'Webpage').substring(0, 22) + '...';
        visibleCountEl.textContent = `${ctx.elements.length} elements`;
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
      console.error(e);
    }
  }

  syncBtn.addEventListener('click', async () => {
    syncBtn.textContent = 'Syncing...';
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) return;

      chrome.tabs.sendMessage(tab.id, { action: 'push_context_to_bridge' }, (response) => {
        if (response && response.success) {
          syncBtn.textContent = '✓ Synced to macOS!';
          statusBadge.textContent = 'App Connected';
          statusBadge.className = 'badge connected';
        } else {
          syncBtn.textContent = 'Sync Failed (App Offline)';
        }
        setTimeout(() => {
          syncBtn.textContent = 'Sync Context to macOS';
        }, 2000);
      });
    } catch (e) {
      syncBtn.textContent = 'Error syncing';
      setTimeout(() => { syncBtn.textContent = 'Sync Context to macOS'; }, 2000);
    }
  });

  await checkBridgeStatus();
  await loadActiveTabContext();
});
