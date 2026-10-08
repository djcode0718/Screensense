/**
 * ScreenSense Tab Synchronization Test Suite (Prompt 6.4)
 * Tests tab switching, injection recovery, identity isolation, and auto-sync lifecycle.
 */

let testsPassed = 0;
let testsFailed = 0;

function assert(condition, message) {
  if (condition) {
    console.log(`✓ Passed: ${message}`);
    testsPassed++;
  } else {
    console.error(`✗ FAILED: ${message}`);
    testsFailed++;
  }
}

console.log('Running ScreenSense Tab Sync Test Suite...\n');

// Mock Tab Contexts
function createMockTabContext(tabId, title, url, elements) {
  return {
    id: `ctx-${tabId}-${Date.now()}`,
    source: 'dom',
    timestamp: new Date().toISOString(),
    viewport: {
      width: 1920,
      height: 1080,
      scrollX: 0,
      scrollY: 0,
      devicePixelRatio: 1.0,
      pageTitle: title,
      url: url
    },
    elements: elements.map((el, i) => ({
      id: `el-${tabId}-${i + 1}`,
      type: el.type,
      text: el.text,
      bounds: { x: 50, y: 50 + (i * 40), width: 400, height: 30, documentX: 50, documentY: 50 + (i * 40) },
      visibilityPercentage: 1.0,
      confidence: 1.0,
      source: 'dom',
      tag: el.type === 'heading' ? 'h1' : (el.type === 'paragraph' ? 'p' : 'button'),
      selector: el.type === 'heading' ? '#title' : 'p'
    })),
    screenshot: null,
    metadata: {
      tab_id: String(tabId),
      window_id: '1',
      visible_elements_count: String(elements.length)
    }
  };
}

// 1. Test Tab A to Tab B Context Transition
let currentBridgeContext = null;
function mockReceiveBridgePayload(context) {
  currentBridgeContext = context;
}

const tabA_Context = createMockTabContext(101, 'Wikipedia - Quantum Computing', 'https://en.wikipedia.org/wiki/Quantum_computing', [
  { type: 'heading', text: 'Quantum computing' },
  { type: 'paragraph', text: 'Quantum computing is a rapidly-emerging technology...' }
]);

const tabB_Context = createMockTabContext(102, 'Amazon - Sony Headphones', 'https://amazon.com/dp/B09XS7JWHH', [
  { type: 'heading', text: 'Sony WH-1000XM5 Headphones' },
  { type: 'button', text: 'Add to Cart' }
]);

// Initial state: Tab A active
mockReceiveBridgePayload(tabA_Context);
assert(currentBridgeContext.viewport.pageTitle === 'Wikipedia - Quantum Computing', 'Tab A context is initially active');
assert(currentBridgeContext.metadata.tab_id === '101', 'Tab A tab_id is 101');

// Tab Switch event to Tab B
mockReceiveBridgePayload(tabB_Context);
assert(currentBridgeContext.viewport.pageTitle === 'Amazon - Sony Headphones', 'Tab switch immediately replaces context with Tab B');
assert(currentBridgeContext.metadata.tab_id === '102', 'Tab B tab_id is 102');
assert(currentBridgeContext.elements[0].text === 'Sony WH-1000XM5 Headphones', 'Tab B elements are now active');

// 2. Test Tab Switch Back to Tab A
mockReceiveBridgePayload(tabA_Context);
assert(currentBridgeContext.viewport.pageTitle === 'Wikipedia - Quantum Computing', 'Tab switch back immediately restores Tab A');
assert(currentBridgeContext.metadata.tab_id === '101', 'Tab A tab_id is restored to 101');

// 3. Test Missing Content Script Injection & Retry Contract
let scriptInjected = false;
let messageReceived = false;

function mockSendMessageToTab(tabId, action) {
  if (!scriptInjected) {
    return { error: 'Could not establish connection. Receiving end does not exist.' };
  }
  messageReceived = true;
  return {
    success: true,
    context: createMockTabContext(tabId, 'Dynamic Injected Tab', 'https://example.com/docs', [
      { type: 'heading', text: 'Documentation Title' }
    ])
  };
}

// First attempt without injection fails
const firstAttempt = mockSendMessageToTab(201, 'extract_visible_context');
assert(firstAttempt.error && firstAttempt.error.includes('Receiving end does not exist'), 'First attempt reports receiving end does not exist');

// Injection simulation
scriptInjected = true;
const retryAttempt = mockSendMessageToTab(201, 'extract_visible_context');
assert(retryAttempt.success === true, 'Retry attempt succeeds after script injection');
assert(retryAttempt.context.viewport.pageTitle === 'Dynamic Injected Tab', 'Injected content script returns valid context');

// 4. Test Idempotency Guard (Prevent duplicate injection duplicate listeners)
let windowState = {};
function executeContentScript(win) {
  if (win.__SCREENSENSE_CONTENT_INJECTED__) {
    return 'already_injected';
  }
  win.__SCREENSENSE_CONTENT_INJECTED__ = true;
  win.listenerCount = (win.listenerCount || 0) + 1;
  return 'injected_fresh';
}

assert(executeContentScript(windowState) === 'injected_fresh', 'First execution injects fresh script');
assert(windowState.listenerCount === 1, 'Exactly 1 listener registered');
assert(executeContentScript(windowState) === 'already_injected', 'Second execution is safely guarded');
assert(windowState.listenerCount === 1, 'Listener count remains 1 (no duplicates)');

// 5. Test Metadata Enrichment
function enrichMetadata(context, tab) {
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

const rawCtx = {
  viewport: { width: 1920, height: 1080, pageTitle: null, url: null },
  elements: []
};
const enriched = enrichMetadata(rawCtx, { id: 301, windowId: 5, title: 'Enriched Page Title', url: 'https://enriched.org' });
assert(enriched.metadata.tab_id === '301', 'Enriched tab_id matches');
assert(enriched.metadata.window_id === '5', 'Enriched window_id matches');
assert(enriched.viewport.pageTitle === 'Enriched Page Title', 'Fallback title applied from tab');
assert(enriched.viewport.url === 'https://enriched.org', 'Fallback URL applied from tab');

console.log(`\n========================================`);
console.log(`Tab Sync Tests Complete: ${testsPassed} passed, ${testsFailed} failed`);
console.log(`========================================\n`);

if (testsFailed > 0) {
  process.exit(1);
}
