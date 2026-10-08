/**
 * Automated tests for ScreenSense VisibilityAnalyzer
 */
const assert = require('assert');
const VisibilityAnalyzer = require('../content/visibility-analyzer.js');

// Mock DOM elements for unit testing
function createMockElement({
  rect = { left: 10, top: 10, width: 200, height: 50, right: 210, bottom: 60 },
  style = { display: 'block', visibility: 'visible', opacity: '1' },
  attributes = {},
  parent = null
} = {}) {
  const el = {
    nodeType: 1,
    hasAttribute: (attr) => attr in attributes,
    getAttribute: (attr) => attributes[attr] !== undefined ? String(attributes[attr]) : null,
    getBoundingClientRect: () => ({ ...rect }),
    parentElement: parent,
    closest: (selector) => {
      let current = el;
      while (current) {
        if (selector === '[aria-hidden="true"]' && current.getAttribute('aria-hidden') === 'true') {
          return current;
        }
        if (selector === '[hidden]' && current.hasAttribute('hidden')) {
          return current;
        }
        if (selector === '[inert]' && current.hasAttribute('inert')) {
          return current;
        }
        current = current.parentElement;
      }
      return null;
    }
  };

  // Mock getComputedStyle
  el._style = style;
  return el;
}

// Set up mock window
global.window = {
  getComputedStyle: (el) => el._style || { display: 'block', visibility: 'visible', opacity: '1' },
  scrollX: 0,
  scrollY: 0
};

console.log('Running VisibilityAnalyzer automated tests...\n');

// Test 1: Standard visible element
{
  const el = createMockElement();
  const res = VisibilityAnalyzer.calculateVisibility(el, 1280, 800);
  assert(res !== null, 'Standard element should be visible');
  assert.strictEqual(res.visibilityPercentage, 1.0, 'Fully visible element should have 100% visibility');
  assert.strictEqual(res.bounds.width, 200);
  console.log('✓ Test 1 Passed: Standard visible element');
}

// Test 2: aria-hidden="true" on self
{
  const el = createMockElement({ attributes: { 'aria-hidden': 'true' } });
  const res = VisibilityAnalyzer.calculateVisibility(el, 1280, 800);
  assert.strictEqual(res, null, 'aria-hidden="true" element must be excluded');
  console.log('✓ Test 2 Passed: Self aria-hidden="true" exclusion');
}

// Test 3: aria-hidden="true" on ancestor
{
  const ancestor = createMockElement({ attributes: { 'aria-hidden': 'true' } });
  const child = createMockElement({ parent: ancestor });
  const res = VisibilityAnalyzer.calculateVisibility(child, 1280, 800);
  assert.strictEqual(res, null, 'Child of aria-hidden="true" ancestor must be excluded');
  console.log('✓ Test 3 Passed: Ancestor aria-hidden="true" exclusion');
}

// Test 4: hidden attribute on self and ancestor
{
  const elSelfHidden = createMockElement({ attributes: { hidden: '' } });
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(elSelfHidden, 1280, 800), null, 'hidden attribute element must be excluded');

  const parentHidden = createMockElement({ attributes: { hidden: '' } });
  const childHidden = createMockElement({ parent: parentHidden });
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(childHidden, 1280, 800), null, 'Child of hidden ancestor must be excluded');
  console.log('✓ Test 4 Passed: [hidden] attribute exclusion on self & ancestor');
}

// Test 5: display: none
{
  const el = createMockElement({ style: { display: 'none', visibility: 'visible', opacity: '1' } });
  const res = VisibilityAnalyzer.calculateVisibility(el, 1280, 800);
  assert.strictEqual(res, null, 'display:none element must be excluded');
  console.log('✓ Test 5 Passed: display:none exclusion');
}

// Test 6: visibility: hidden
{
  const el = createMockElement({ style: { display: 'block', visibility: 'hidden', opacity: '1' } });
  const res = VisibilityAnalyzer.calculateVisibility(el, 1280, 800);
  assert.strictEqual(res, null, 'visibility:hidden element must be excluded');
  console.log('✓ Test 6 Passed: visibility:hidden exclusion');
}

// Test 7: opacity: 0 on self or ancestor
{
  const elSelf = createMockElement({ style: { display: 'block', visibility: 'visible', opacity: '0' } });
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(elSelf, 1280, 800), null, 'opacity:0 element must be excluded');

  const ancestor = createMockElement({ style: { display: 'block', visibility: 'visible', opacity: '0' } });
  const child = createMockElement({ parent: ancestor });
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(child, 1280, 800), null, 'Child of opacity:0 ancestor must be excluded');
  console.log('✓ Test 7 Passed: opacity:0 exclusion on self & ancestor');
}

// Test 8: Zero dimensions
{
  const elZeroW = createMockElement({ rect: { left: 0, top: 0, width: 0, height: 50, right: 0, bottom: 50 } });
  const elZeroH = createMockElement({ rect: { left: 0, top: 0, width: 50, height: 0, right: 50, bottom: 0 } });
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(elZeroW, 1280, 800), null, 'Zero width must be excluded');
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(elZeroH, 1280, 800), null, 'Zero height must be excluded');
  console.log('✓ Test 8 Passed: Zero dimensions exclusion');
}

// Test 9: Outside viewport (above, below, left, right)
{
  const elAbove = createMockElement({ rect: { left: 10, top: -200, width: 100, height: 100, right: 110, bottom: -100 } });
  const elBelow = createMockElement({ rect: { left: 10, top: 900, width: 100, height: 100, right: 110, bottom: 1000 } });
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(elAbove, 1280, 800), null, 'Element above viewport must be excluded');
  assert.strictEqual(VisibilityAnalyzer.calculateVisibility(elBelow, 1280, 800), null, 'Element below viewport must be excluded');
  console.log('✓ Test 9 Passed: Outside viewport exclusion');
}

// Test 10: Partially visible element (50% cut off at viewport bottom edge)
{
  // Total height = 100px, top is at 750px in an 800px high viewport (50px visible)
  const elPartial = createMockElement({
    rect: { left: 10, top: 750, width: 100, height: 100, right: 110, bottom: 850 }
  });
  const res = VisibilityAnalyzer.calculateVisibility(elPartial, 1280, 800);
  assert(res !== null, 'Partially visible element should be returned');
  assert.strictEqual(res.visibilityPercentage, 0.5, '50% visible element must report 0.5');
  assert.strictEqual(res.isFullyVisible, false);
  console.log('✓ Test 10 Passed: Partially visible element calculation');
}

console.log('\nAll 10 VisibilityAnalyzer tests passed successfully!');
