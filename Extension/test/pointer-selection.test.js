const assert = require('assert');

// Mock browser environment
global.window = {
  innerWidth: 1920,
  innerHeight: 1080,
  scrollX: 0,
  scrollY: 0,
  devicePixelRatio: 2.0,
  location: { href: 'https://en.wikipedia.org/wiki/Quantum_computing' },
  __SCREENSENSE_LAST_POINTER__: { x: 350, y: 220 },
  getSelection: () => ({
    isCollapsed: false,
    toString: () => 'quantum entanglement',
    rangeCount: 1,
    getRangeAt: () => ({
      getBoundingClientRect: () => ({
        left: 300,
        top: 200,
        width: 140,
        height: 25
      }),
      commonAncestorContainer: {
        nodeType: 1,
        id: 'para-quantum-info',
        parentElement: null
      }
    })
  })
};

global.document = {
  title: 'Quantum computing - Wikipedia',
  readyState: 'complete',
  documentElement: {
    clientWidth: 1920,
    clientHeight: 1080
  },
  querySelectorAll: () => []
};

global.window.ScreenSenseVisibilityAnalyzer = {
  calculateVisibility: () => null
};

const DOMAnalyzer = require('../content/dom-analyzer');

console.log('Running Pointer & Selection Context JavaScript tests...\n');

const context = DOMAnalyzer.extractVisibleContext();

// Test 1: Pointer context extracted
assert(context.pointer !== null, 'Pointer context should not be null');
assert.strictEqual(context.pointer.x, 350, 'Pointer x should be 350');
assert.strictEqual(context.pointer.y, 220, 'Pointer y should be 220');
console.log('✓ Test 1 Passed: Pointer coordinates extracted properly');

// Test 2: Selection context extracted
assert(context.selection !== null, 'Selection context should not be null');
assert.strictEqual(context.selection.text, 'quantum entanglement', 'Selected text should match');
assert.strictEqual(context.selection.bounds.x, 300, 'Selection bound X should match');
assert.strictEqual(context.selection.bounds.width, 140, 'Selection bound width should match');
assert.strictEqual(context.selection.containingElementId, 'para-quantum-info', 'Containing element ID should match');
console.log('✓ Test 2 Passed: Selection context and bounding box extracted properly');

// Test 3: Collapsed selection produces null selection
global.window.getSelection = () => ({
  isCollapsed: true,
  toString: () => ''
});
const noSelContext = DOMAnalyzer.extractVisibleContext();
assert.strictEqual(noSelContext.selection, null, 'Collapsed selection should result in null selection context');
console.log('✓ Test 3 Passed: Empty / collapsed selection handled gracefully as null');

console.log('\n========================================');
console.log('Pointer & Selection Tests Complete: All passed');
console.log('========================================\n');
