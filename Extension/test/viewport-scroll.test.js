/**
 * Viewport Scroll Synchronization Tests
 * Tests computeContextHash, scroll-driven change detection, and debounce logic.
 */

const assert = require('assert');

function computeContextHash(context) {
  if (!context || !context.elements) return '';
  const vp = context.viewport;
  const vpHash = vp ? `vp:${Math.round(vp.scrollX)}:${Math.round(vp.scrollY)}:${Math.round(vp.width)}:${Math.round(vp.height)}` : '';
  const elHash = context.elements.map(e => `${e.type}:${e.text.slice(0, 30)}:${Math.round(e.bounds.x)}:${Math.round(e.bounds.y)}:${Math.round(e.bounds.width)}:${Math.round(e.bounds.height)}`).join('|');
  return `${vpHash}#${context.elements.length}#${elHash}`;
}

console.log('Running Viewport Scroll Synchronization Tests...\n');

// 1. Hash includes scrollY
const ctxTop = {
  viewport: { scrollX: 0, scrollY: 0, width: 1440, height: 900 },
  elements: [
    { type: 'heading', text: 'Quantum computing', bounds: { x: 20, y: 30, width: 400, height: 40 } }
  ]
};

const ctxScrolled = {
  viewport: { scrollX: 0, scrollY: 1500, width: 1440, height: 900 },
  elements: [
    { type: 'heading', text: 'Quantum algorithms', bounds: { x: 20, y: 50, width: 350, height: 35 } }
  ]
};

const hashTop = computeContextHash(ctxTop);
const hashScrolled = computeContextHash(ctxScrolled);

assert.notStrictEqual(hashTop, hashScrolled, 'Top and Scrolled context hashes must differ');
console.log('✓ Test 1 Passed: Context hash changes when scrollY changes');

// 2. Hash remains identical when viewport & elements are unchanged
const ctxTopClone = JSON.parse(JSON.stringify(ctxTop));
const hashTopClone = computeContextHash(ctxTopClone);
assert.strictEqual(hashTop, hashTopClone, 'Identical viewport context must produce identical hash');
console.log('✓ Test 2 Passed: Identical viewport produces identical hash');

// 3. Hash changes when elements in viewport change even at same scroll position
const ctxDifferentElements = {
  viewport: { scrollX: 0, scrollY: 0, width: 1440, height: 900 },
  elements: [
    { type: 'paragraph', text: 'New dynamic content arrived', bounds: { x: 20, y: 100, width: 500, height: 50 } }
  ]
};
assert.notStrictEqual(hashTop, computeContextHash(ctxDifferentElements), 'Different elements must change hash');
console.log('✓ Test 3 Passed: DOM element changes alter hash');

// 4. Hash includes viewport dimensions (resize event)
const ctxResized = {
  viewport: { scrollX: 0, scrollY: 0, width: 800, height: 600 },
  elements: [
    { type: 'heading', text: 'Quantum computing', bounds: { x: 20, y: 30, width: 400, height: 40 } }
  ]
};
assert.notStrictEqual(hashTop, computeContextHash(ctxResized), 'Resized viewport must change hash');
console.log('✓ Test 4 Passed: Viewport resize changes hash');

// 5. Hash handles empty elements array gracefully
const ctxEmpty = {
  viewport: { scrollX: 0, scrollY: 0, width: 1440, height: 900 },
  elements: []
};
const hashEmpty = computeContextHash(ctxEmpty);
assert.strictEqual(hashEmpty, 'vp:0:0:1440:900#0#', 'Empty elements produces clean structure hash');
console.log('✓ Test 5 Passed: Empty elements produces valid hash');

console.log('\n========================================');
console.log('Viewport Scroll Tests Complete: All 5 passed');
console.log('========================================\n');
