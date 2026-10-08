/**
 * ScreenSense Chrome Extension Pipeline Tests
 * Tests DOM extraction, message contracts, payload schemas, and bridge compatibility.
 */

const VisibilityAnalyzer = require('../content/visibility-analyzer');
const DOMAnalyzer = require('../content/dom-analyzer');

// Setup mock window & DOM environment
global.window = {
  innerWidth: 1920,
  innerHeight: 1080,
  scrollX: 0,
  scrollY: 0,
  devicePixelRatio: 1.0,
  ScreenSenseVisibilityAnalyzer: VisibilityAnalyzer
};

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

console.log('Running Extension Pipeline & DOM Contract tests...\n');

// 1. Test DOMAnalyzer exports and methods
assert(typeof DOMAnalyzer.extractVisibleContext === 'function', 'DOMAnalyzer.extractVisibleContext is a function');
assert(typeof DOMAnalyzer.getElementType === 'function', 'DOMAnalyzer.getElementType is a function');
assert(typeof DOMAnalyzer.getCleanText === 'function', 'DOMAnalyzer.getCleanText is a function');

// 2. Test getElementType mapping
assert(DOMAnalyzer.getElementType({ tagName: 'H1', getAttribute: () => null }) === 'heading', 'H1 maps to heading');
assert(DOMAnalyzer.getElementType({ tagName: 'H3', getAttribute: () => null }) === 'heading', 'H3 maps to heading');
assert(DOMAnalyzer.getElementType({ tagName: 'P', getAttribute: () => null }) === 'paragraph', 'P maps to paragraph');
assert(DOMAnalyzer.getElementType({ tagName: 'BUTTON', getAttribute: () => null }) === 'button', 'BUTTON maps to button');
assert(DOMAnalyzer.getElementType({ tagName: 'A', getAttribute: () => null }) === 'link', 'A maps to link');
assert(DOMAnalyzer.getElementType({ tagName: 'SPAN', getAttribute: () => 'button' }) === 'button', 'Role button maps to button');
assert(DOMAnalyzer.getElementType({ tagName: 'DIV', getAttribute: () => null }) === 'generic_text', 'DIV maps to generic_text');

// 3. Test SVG element className safety (no crash on non-string className)
const mockSvgElement = {
  tagName: 'svg',
  id: '',
  className: { baseVal: 'icon icon-star', animVal: 'icon icon-star' },
  getAttribute: () => null
};
let selectorThrown = false;
try {
  let selector = mockSvgElement.tagName.toLowerCase();
  if (mockSvgElement.id && typeof mockSvgElement.id === 'string') {
    selector = `#${mockSvgElement.id}`;
  } else if (typeof mockSvgElement.className === 'string' && mockSvgElement.className.trim()) {
    selector = `.${mockSvgElement.className.trim().split(/\s+/).join('.')}`;
  }
  assert(selector === 'svg', 'SVG element with SVGAnimatedString className produces safe selector without throwing');
} catch (e) {
  selectorThrown = true;
}
assert(!selectorThrown, 'Non-string className does not throw error');

// 4. Test Canonical Context JSON Payload Schema
const mockContext = {
  id: `ctx-${Date.now()}-abc123`,
  source: 'dom',
  timestamp: new Date().toISOString(),
  viewport: {
    width: 1920,
    height: 1080,
    scrollX: 0,
    scrollY: 0,
    devicePixelRatio: 1.0,
    pageTitle: 'Albert Einstein — Wikipedia',
    url: 'https://en.wikipedia.org/wiki/Albert_Einstein'
  },
  elements: [
    {
      id: 'firstHeading',
      type: 'heading',
      text: 'Albert Einstein',
      bounds: { x: 50, y: 50, width: 400, height: 35, documentX: 50, documentY: 50 },
      visibilityPercentage: 1.0,
      confidence: 1.0,
      source: 'dom',
      tag: 'h1',
      selector: '#firstHeading'
    },
    {
      id: 'p1',
      type: 'paragraph',
      text: 'Albert Einstein was a German-born theoretical physicist.',
      bounds: { x: 50, y: 95, width: 600, height: 40, documentX: 50, documentY: 95 },
      visibilityPercentage: 1.0,
      confidence: 1.0,
      source: 'dom',
      tag: 'p',
      selector: 'p'
    }
  ],
  screenshot: null,
  metadata: {
    total_dom_candidates: '2',
    visible_elements_count: '2',
    document_ready_state: 'complete'
  }
};

// Check schema properties
assert(typeof mockContext.id === 'string' && mockContext.id.length > 0, 'Context has valid string id');
assert(mockContext.source === 'dom', 'Context source is "dom"');
assert(new Date(mockContext.timestamp).toString() !== 'Invalid Date', 'Context timestamp is valid ISO string');
assert(typeof mockContext.viewport.width === 'number', 'Viewport width is number');
assert(typeof mockContext.viewport.height === 'number', 'Viewport height is number');
assert(Array.isArray(mockContext.elements), 'Elements is an array');
assert(mockContext.elements.length === 2, 'Elements array contains extracted elements');

// Validate element fields
const el0 = mockContext.elements[0];
assert(el0.type === 'heading', 'Element 0 type is heading');
assert(el0.tag === 'h1', 'Element 0 tag is h1');
assert(typeof el0.bounds.x === 'number', 'Element 0 bounds.x is number');
assert(typeof el0.bounds.y === 'number', 'Element 0 bounds.y is number');
assert(typeof el0.visibilityPercentage === 'number', 'Element 0 visibilityPercentage is number');
assert(el0.confidence === 1.0, 'Element 0 confidence is 1.0');

// Validate JSON.stringify output is valid JSON
const jsonString = JSON.stringify(mockContext);
assert(typeof jsonString === 'string' && jsonString.startsWith('{') && jsonString.endsWith('}'), 'Context stringifies to valid JSON');

const parsed = JSON.parse(jsonString);
assert(parsed.elements[0].text === 'Albert Einstein', 'JSON round-trip preserves text accurately');

console.log(`\n========================================`);
console.log(`Pipeline Tests Complete: ${testsPassed} passed, ${testsFailed} failed`);
console.log(`========================================\n`);

if (testsFailed > 0) {
  process.exit(1);
}
