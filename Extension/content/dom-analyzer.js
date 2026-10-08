/**
 * ScreenSense DOM Analyzer
 * Traverses DOM tree, extracts textual and interactive elements,
 * filters for current viewport visibility, and produces a structured VisibleContext payload.
 */
class DOMAnalyzer {
  /**
   * Maps HTML Tag to semantic ElementType
   * @param {Element} element
   * @returns {string}
   */
  static getElementType(element) {
    const tag = element.tagName.toLowerCase();
    if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tag)) {
      return 'heading';
    }
    if (tag === 'p') {
      return 'paragraph';
    }
    if (tag === 'li') {
      return 'list_item';
    }
    if (tag === 'blockquote') {
      return 'blockquote';
    }
    if (tag === 'pre' || tag === 'code') {
      return 'code';
    }
    if (tag === 'button' || element.getAttribute('role') === 'button') {
      return 'button';
    }
    if (tag === 'a') {
      return 'link';
    }
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
      return 'input';
    }
    return 'generic_text';
  }

  /**
   * Extracts clean text content from an element
   * @param {Element} element
   * @returns {string}
   */
  static getCleanText(element) {
    const tag = element.tagName.toLowerCase();
    if (tag === 'input' || tag === 'textarea') {
      return (element.value || element.placeholder || '').trim();
    }
    if (tag === 'select') {
      return (element.options[element.selectedIndex]?.text || '').trim();
    }
    // Remove inline scripts and style contents if any
    const clone = element.cloneNode(true);
    const removeTags = clone.querySelectorAll('script, style, noscript');
    removeTags.forEach(n => n.remove());

    return (clone.textContent || '').replace(/\s+/g, ' ').trim();
  }

  /**
   * Extracts all visible elements in current viewport
   * @returns {Object} VisibleContext payload
   */
  static extractVisibleContext() {
    const viewportWidth = window.innerWidth || document.documentElement.clientWidth;
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight;

    const selectors = [
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'p',
      'span',
      'label',
      'strong',
      'em',
      'dt',
      'dd',
      'li',
      'blockquote',
      'pre',
      'code',
      'button',
      'a[href]',
      'input:not([type="hidden"])',
      'textarea',
      'article',
      'section',
      '[role="heading"]',
      '[role="button"]',
      '[role="article"]'
    ];

    const candidates = Array.from(document.querySelectorAll(selectors.join(',')));
    const processedElements = [];
    const seenTexts = new Set();

    for (let index = 0; index < candidates.length; index++) {
      const element = candidates[index];
      const text = this.getCleanText(element);

      // Skip empty text
      if (!text || text.length === 0) continue;

      // Skip elements whose children already represent the text exactly
      // (prevents parent article/section/div duplicate of individual paragraphs/spans)
      const hasSpecificChild = candidates.some(other =>
        other !== element &&
        element.contains(other) &&
        ['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'span', 'label', 'strong', 'button', 'a'].includes(other.tagName.toLowerCase())
      );
      if (hasSpecificChild && ['article', 'section', 'div', 'p', 'li'].includes(element.tagName.toLowerCase())) {
        continue;
      }

      const visibility = window.ScreenSenseVisibilityAnalyzer.calculateVisibility(
        element,
        viewportWidth,
        viewportHeight
      );

      if (!visibility) continue;

      const type = this.getElementType(element);
      const id = element.id || `el-${processedElements.length + 1}-${Math.random().toString(36).substr(2, 6)}`;

      processedElements.push({
        id: id,
        type: type,
        text: text,
        bounds: visibility.bounds,
        visibilityPercentage: visibility.visibilityPercentage,
        confidence: 1.0,
        source: 'dom',
        tag: element.tagName.toLowerCase(),
        selector: element.id ? `#${element.id}` : (element.className ? `.${element.className.split(' ').join('.')}` : element.tagName.toLowerCase())
      });
    }

    // Sort in visual reading order (top-to-bottom, left-to-right)
    processedElements.sort((a, b) => {
      const yDiff = a.bounds.y - b.bounds.y;
      if (Math.abs(yDiff) > 12) {
        return yDiff;
      }
      return a.bounds.x - b.bounds.x;
    });

    const viewportInfo = {
      width: viewportWidth,
      height: viewportHeight,
      scrollX: Math.round(window.scrollX * 10) / 10,
      scrollY: Math.round(window.scrollY * 10) / 10,
      devicePixelRatio: window.devicePixelRatio || 1.0,
      pageTitle: document.title || null,
      url: window.location.href || null
    };

    return {
      id: `ctx-${Date.now()}-${Math.random().toString(36).substr(2, 6)}`,
      source: 'dom',
      timestamp: new Date().toISOString(),
      viewport: viewportInfo,
      elements: processedElements,
      screenshot: null,
      metadata: {
        total_dom_candidates: `${candidates.length}`,
        visible_elements_count: `${processedElements.length}`,
        document_ready_state: document.readyState
      }
    };
  }
}

// Expose globally for content scripts and test environments
if (typeof window !== 'undefined') {
  window.ScreenSenseDOMAnalyzer = DOMAnalyzer;
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = DOMAnalyzer;
}
