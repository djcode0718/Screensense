/**
 * ScreenSense Visibility Analyzer
 * Calculates precise viewport visibility metrics for DOM elements.
 */
class VisibilityAnalyzer {
  /**
   * Checks if an element is structurally hidden via CSS or HTML attributes.
   * Checks both the element itself and all its ancestor containers.
   * @param {Element} element
   * @param {CSSStyleDeclaration} [computedStyle]
   * @returns {boolean}
   */
  static isStructurallyHidden(element, computedStyle) {
    if (!element || element.nodeType !== 1) return true;

    // 1. Check self or any ancestor for aria-hidden="true"
    if (element.closest && element.closest('[aria-hidden="true"]')) {
      return true;
    }

    // 2. Check self or any ancestor for the HTML hidden attribute
    if (element.closest && element.closest('[hidden]')) {
      return true;
    }

    // 3. Check self or any ancestor for inert attribute
    if (element.closest && element.closest('[inert]')) {
      return true;
    }

    // 4. Check self computed styles
    const style = computedStyle || window.getComputedStyle(element);
    if (!style) return true;

    if (style.display === 'none') return true;
    if (style.visibility === 'hidden' || style.visibility === 'collapse') return true;
    if (parseFloat(style.opacity) === 0) return true;

    // 5. Walk ancestor tree to check for parent display:none, visibility:hidden, or opacity:0
    let parent = element.parentElement;
    const bodyEl = (typeof document !== 'undefined') ? document.body : null;
    const docEl = (typeof document !== 'undefined') ? document.documentElement : null;
    while (parent && parent !== bodyEl && parent !== docEl) {
      const pStyle = (typeof window !== 'undefined') ? window.getComputedStyle(parent) : null;
      if (
        pStyle &&
        (pStyle.display === 'none' ||
        pStyle.visibility === 'hidden' ||
        pStyle.visibility === 'collapse' ||
        parseFloat(pStyle.opacity) === 0)
      ) {
        return true;
      }
      parent = parent.parentElement;
    }

    return false;
  }

  /**
   * Calculates visibility percentage and geometry of an element in current viewport.
   * @param {Element} element
   * @param {number} viewportWidth
   * @param {number} viewportHeight
   * @returns {Object|null}
   */
  static calculateVisibility(element, viewportWidth, viewportHeight) {
    const style = window.getComputedStyle(element);
    if (this.isStructurallyHidden(element, style)) {
      return null;
    }

    const rect = element.getBoundingClientRect();

    // Zero-dimension element check
    if (rect.width <= 0 || rect.height <= 0) {
      return null;
    }

    // Completely outside viewport bounds
    if (
      rect.bottom <= 0 ||
      rect.top >= viewportHeight ||
      rect.right <= 0 ||
      rect.left >= viewportWidth
    ) {
      return null;
    }

    // Viewport intersection bounds
    const visibleLeft = Math.max(0, rect.left);
    const visibleRight = Math.min(viewportWidth, rect.right);
    const visibleTop = Math.max(0, rect.top);
    const visibleBottom = Math.min(viewportHeight, rect.bottom);

    const visibleWidth = Math.max(0, visibleRight - visibleLeft);
    const visibleHeight = Math.max(0, visibleBottom - visibleTop);
    const visibleArea = visibleWidth * visibleHeight;
    const totalArea = rect.width * rect.height;

    const visibilityPercentage = totalArea > 0 ? (visibleArea / totalArea) : 0;

    // Filter out negligible slivers (< 2% or 0 visible area)
    if (visibleArea <= 0 || visibilityPercentage < 0.02) {
      return null;
    }

    return {
      bounds: {
        x: Math.round(rect.left * 10) / 10,
        y: Math.round(rect.top * 10) / 10,
        width: Math.round(rect.width * 10) / 10,
        height: Math.round(rect.height * 10) / 10,
        documentX: Math.round((rect.left + window.scrollX) * 10) / 10,
        documentY: Math.round((rect.top + window.scrollY) * 10) / 10
      },
      visibilityPercentage: Math.round(visibilityPercentage * 100) / 100,
      isFullyVisible: visibilityPercentage >= 0.99
    };
  }
}

// Expose globally for content scripts and test environments
if (typeof window !== 'undefined') {
  window.ScreenSenseVisibilityAnalyzer = VisibilityAnalyzer;
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = VisibilityAnalyzer;
}
