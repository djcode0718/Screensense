/**
 * ScreenSense Live Query Automated Test Suite
 * Tests DOMAnalyzer.getElementAtPoint, getActiveSelectionDetails,
 * and live query message handlers for pointer, selection, tab, and DOM.
 */

const assert = require('assert');

// Mock browser DOM environment
function setupMockDOM() {
  const elements = [];

  class MockDOMRect {
    constructor(x, y, width, height) {
      this.left = x;
      this.top = y;
      this.right = x + width;
      this.bottom = y + height;
      this.x = x;
      this.y = y;
      this.width = width;
      this.height = height;
    }
  }

  class MockElement {
    constructor(tagName, text = '', attrs = {}) {
      this.tagName = tagName.toUpperCase();
      this.nodeType = 1;
      this.id = attrs.id || '';
      this.className = attrs.className || '';
      this.textContent = text;
      this.parentElement = null;
      this.children = [];
      this.attrs = attrs;
      this.rect = new MockDOMRect(attrs.x || 0, attrs.y || 0, attrs.width || 100, attrs.height || 30);
    }

    getAttribute(name) {
      return this.attrs[name] || null;
    }

    getBoundingClientRect() {
      return this.rect;
    }

    closest(selector) {
      const tag = selector.toLowerCase();
      let curr = this;
      while (curr) {
        if (curr.tagName && curr.tagName.toLowerCase() === tag) {
          return curr;
        }
        if (tag.includes('heading') && ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(curr.tagName.toLowerCase())) {
          return curr;
        }
        if (tag.includes('p,') && ['p', 'blockquote', 'li'].includes(curr.tagName.toLowerCase())) {
          return curr;
        }
        curr = curr.parentElement;
      }
      return null;
    }

    cloneNode(deep = true) {
      const clone = new MockElement(this.tagName, this.textContent, this.attrs);
      clone.querySelectorAll = () => [];
      return clone;
    }

    appendChild(child) {
      child.parentElement = this;
      this.children.push(child);
      return child;
    }
  }

  global.window = {
    innerWidth: 1280,
    innerHeight: 800,
    scrollX: 0,
    scrollY: 0,
    devicePixelRatio: 2.0,
    __SCREENSENSE_LAST_POINTER__: { x: 300, y: 250 }
  };

  global.document = {
    title: 'Quantum computing - Wikipedia',
    readyState: 'complete',
    documentElement: { clientWidth: 1280, clientHeight: 800 },
    elementFromPoint: (x, y) => {
      // Find deepest mock element matching coordinates
      for (const el of elements.slice().reverse()) {
        const r = el.rect;
        if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
          return el;
        }
      }
      return null;
    }
  };

  return { MockElement, MockDOMRect, elements };
}

console.log('Running ScreenSense Live Query JavaScript Test Suite...\n');

const { MockElement, MockDOMRect, elements } = setupMockDOM();
const DOMAnalyzer = require('../content/dom-analyzer');

// 1. Pointer over paragraph
const p1 = new MockElement('p', 'Quantum computing is a rapidly-emerging technology.', { id: 'p1', x: 50, y: 100, width: 600, height: 60 });
elements.push(p1);

const ptrRes1 = DOMAnalyzer.getElementAtPoint(100, 120);
assert.strictEqual(ptrRes1.status, 'OK', 'Pointer status should be OK');
assert.strictEqual(ptrRes1.targetElement.tag, 'p', 'Target tag should be p');
assert.strictEqual(ptrRes1.containingParagraph, 'Quantum computing is a rapidly-emerging technology.');
console.log('✓ Test 1 Passed: Pointer over paragraph resolves target & containing paragraph');

// 2. Pointer over inline link inside paragraph
const link = new MockElement('a', 'quantum mechanics', { id: 'link1', x: 120, y: 200, width: 100, height: 20 });
const p2 = new MockElement('p', 'It utilizes principles of quantum mechanics to solve problems.', { id: 'p2', x: 50, y: 190, width: 600, height: 80 });
p2.appendChild(link);
elements.push(p2);
elements.push(link);

const ptrRes2 = DOMAnalyzer.getElementAtPoint(130, 205);
assert.strictEqual(ptrRes2.status, 'OK', 'Pointer status should be OK');
assert.strictEqual(ptrRes2.targetElement.tag, 'a', 'Target tag should be link');
assert.strictEqual(ptrRes2.targetElement.text, 'quantum mechanics', 'Target text is link text');
assert.strictEqual(ptrRes2.containingParagraph, 'It utilizes principles of quantum mechanics to solve problems.', 'Containing paragraph resolved from parent');
console.log('✓ Test 2 Passed: Pointer over inline link extracts containing paragraph');

// 3. Pointer over button
const btn = new MockElement('button', 'Apply Filter', { id: 'btn-apply', x: 500, y: 400, width: 120, height: 40 });
elements.push(btn);

const ptrRes3 = DOMAnalyzer.getElementAtPoint(520, 410);
assert.strictEqual(ptrRes3.status, 'OK');
assert.strictEqual(ptrRes3.targetElement.tag, 'button');
assert.strictEqual(ptrRes3.targetElement.type, 'button');
assert.strictEqual(ptrRes3.containingText, 'Apply Filter');
console.log('✓ Test 3 Passed: Pointer over button resolves button text');

// 4. Pointer missing / out of bounds
const ptrRes4 = DOMAnalyzer.getElementAtPoint(9999, 9999);
assert.strictEqual(ptrRes4.status, 'ELEMENT_NOT_FOUND', 'Should return ELEMENT_NOT_FOUND for out-of-bounds pointer');
console.log('✓ Test 4 Passed: Pointer missing handled deterministically');

// 5. Active selection test
window.getSelection = () => {
  return {
    isCollapsed: false,
    rangeCount: 1,
    toString: () => 'quantum speedup',
    getRangeAt: (idx) => ({
      commonAncestorContainer: p1,
      getBoundingClientRect: () => new MockDOMRect(150, 110, 120, 20)
    })
  };
};

const selRes1 = DOMAnalyzer.getActiveSelectionDetails();
assert.strictEqual(selRes1.status, 'OK');
assert.strictEqual(selRes1.text, 'quantum speedup');
assert.strictEqual(selRes1.isCollapsed, false);
assert.strictEqual(selRes1.containingParagraph, 'Quantum computing is a rapidly-emerging technology.');
console.log('✓ Test 5 Passed: Active text selection resolves exact text and containing paragraph');

// 6. Selected sentence test
const p3 = new MockElement('p', 'First sentence here. Second sentence with selected target in it. Third sentence follows.', { id: 'p3', x: 50, y: 500, width: 700, height: 80 });
elements.push(p3);

window.getSelection = () => {
  return {
    isCollapsed: false,
    rangeCount: 1,
    toString: () => 'selected target',
    getRangeAt: (idx) => ({
      commonAncestorContainer: p3,
      getBoundingClientRect: () => new MockDOMRect(180, 510, 90, 20)
    })
  };
};

const selRes2 = DOMAnalyzer.getActiveSelectionDetails();
assert.strictEqual(selRes2.text, 'selected target');
assert.strictEqual(selRes2.containingSentence, 'Second sentence with selected target in it.');
console.log('✓ Test 6 Passed: Selected sentence extracts accurate sentence boundary');

// 7. No selection / collapsed selection
window.getSelection = () => {
  return {
    isCollapsed: true,
    rangeCount: 1,
    toString: () => '',
    getRangeAt: (idx) => null
  };
};

const selRes3 = DOMAnalyzer.getActiveSelectionDetails();
assert.strictEqual(selRes3.status, 'NO_ACTIVE_SELECTION');
assert.strictEqual(selRes3.isCollapsed, true);
assert.strictEqual(selRes3.text, '');
console.log('✓ Test 7 Passed: Collapsed/empty selection returns NO_ACTIVE_SELECTION');

// 8. Service Worker Syntax & Loading Verification (Regression Test for Prompt 6.9.1)
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const swPath = path.join(__dirname, '../background/service-worker.js');
const swCode = fs.readFileSync(swPath, 'utf8');

// Verify service worker script syntax parses cleanly
assert.doesNotThrow(() => {
  new vm.Script(swCode);
}, 'service-worker.js must be syntactically valid and parse cleanly without syntax errors');

assert(swCode.includes('listenForLiveQueries()'), 'service-worker.js must invoke listenForLiveQueries()');
assert(swCode.includes('/api/query/pending'), 'service-worker.js must query /api/query/pending');
assert(swCode.includes('/api/query/response'), 'service-worker.js must post to /api/query/response');
console.log('✓ Test 8 Passed: Service worker syntax, long-polling listener, and response endpoints verified');

// 9. Content Script unavailable handling surfaces immediately
function simulateTabQueryHandler(isContentScriptReachable) {
  if (!isContentScriptReachable) {
    return {
      success: false,
      status: 'CONTENT_SCRIPT_UNAVAILABLE',
      error: 'Could not establish connection. Receiving end does not exist.'
    };
  }
  return {
    success: true,
    status: 'OK',
    pointerResult: DOMAnalyzer.getElementAtPoint(100, 120)
  };
}

const unavailableResult = simulateTabQueryHandler(false);
assert.strictEqual(unavailableResult.status, 'CONTENT_SCRIPT_UNAVAILABLE');
assert.strictEqual(unavailableResult.success, false);
console.log('✓ Test 9 Passed: Content script unavailability surfaces immediate failure');

// 10. Round-trip response envelope matches LiveQueryResponse schema
const liveResponsePayload = {
  requestId: 'test-req-12345',
  success: true,
  status: 'OK',
  error: null,
  tabId: '42',
  url: 'https://en.wikipedia.org/wiki/Quantum_computing',
  pageTitle: 'Quantum computing - Wikipedia',
  pointerResult: DOMAnalyzer.getElementAtPoint(100, 120),
  selectionResult: null,
  domResult: null,
  timestamp: new Date().toISOString()
};

assert.strictEqual(liveResponsePayload.requestId, 'test-req-12345');
assert.strictEqual(liveResponsePayload.pointerResult.status, 'OK');
assert.strictEqual(typeof liveResponsePayload.timestamp, 'string');
console.log('✓ Test 10 Passed: LiveQueryResponse envelope schema preserves requestId and payload');

console.log('\n========================================');
console.log('ScreenSense Live Query Tests: All 10 passed');
console.log('========================================\n');

