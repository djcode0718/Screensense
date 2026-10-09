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
      const id = element.id || `el-${processedElements.length + 1}-${type}`;

      let selector = element.tagName.toLowerCase();
      if (element.id && typeof element.id === 'string') {
        selector = `#${element.id}`;
      } else if (typeof element.className === 'string' && element.className.trim()) {
        const classNames = element.className.trim().split(/\s+/).filter(Boolean);
        if (classNames.length > 0) {
          selector = `.${classNames.join('.')}`;
        }
      }

      processedElements.push({
        id: id,
        type: type,
        text: text,
        bounds: visibility.bounds,
        visibilityPercentage: visibility.visibilityPercentage,
        confidence: 1.0,
        source: 'dom',
        tag: element.tagName.toLowerCase(),
        selector: selector
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

    // Selection context extraction
    let selectionContext = null;
    try {
      const sel = (typeof window !== 'undefined' && window.getSelection) ? window.getSelection() : null;
      if (sel && !sel.isCollapsed && sel.toString().trim().length > 0) {
        const selText = sel.toString().trim();
        let bounds = null;
        let containingElementId = null;
        if (sel.rangeCount > 0) {
          const range = sel.getRangeAt(0);
          const rect = range.getBoundingClientRect();
          if (rect) {
            bounds = {
              x: Math.round(rect.left),
              y: Math.round(rect.top),
              width: Math.round(rect.width),
              height: Math.round(rect.height)
            };
          }
          let ancestor = range.commonAncestorContainer;
          if (ancestor && ancestor.nodeType === 3) {
            ancestor = ancestor.parentElement;
          }
          if (ancestor && ancestor.id) {
            containingElementId = ancestor.id;
          }
        }
        selectionContext = {
          text: selText,
          bounds: bounds,
          containingElementId: containingElementId,
          containingRegionId: null,
          startOffset: null,
          endOffset: null
        };
      }
    } catch (e) {
      // Ignore in mock/test environments
    }

    // Pointer context extraction
    let pointerContext = null;
    try {
      const lastPointer = (typeof window !== 'undefined') ? window.__SCREENSENSE_LAST_POINTER__ : null;
      if (lastPointer && typeof lastPointer.x === 'number' && typeof lastPointer.y === 'number') {
        pointerContext = {
          x: lastPointer.x,
          y: lastPointer.y,
          elementId: null,
          containingRegionId: null
        };
      }
    } catch (e) {
      // Ignore
    }

    return {
      id: `ctx-${Date.now()}-${Math.random().toString(36).substr(2, 6)}`,
      source: 'dom',
      timestamp: new Date().toISOString(),
      viewport: viewportInfo,
      elements: processedElements,
      screenshot: null,
      pointer: pointerContext,
      selection: selectionContext,
      metadata: {
        total_dom_candidates: `${candidates.length}`,
        visible_elements_count: `${processedElements.length}`,
        document_ready_state: document.readyState
      }
    };
  }

  /**
   * Command-time Live Pointer query: inspects the element under coordinates (x, y)
   * and computes containing meaningful text containers, paragraph, heading, and section.
   * @param {number} x
   * @param {number} y
   * @returns {Object}
   */
  static getElementAtPoint(x, y) {
    if (typeof document === 'undefined' || !document.elementFromPoint) {
      return { status: 'POINTER_UNAVAILABLE', x, y };
    }
    if (typeof x !== 'number' || typeof y !== 'number' || isNaN(x) || isNaN(y)) {
      return { status: 'POINTER_UNAVAILABLE', x: 0, y: 0 };
    }

    console.log(`[SS-LIVEQUERY] pointer:\nx=${x}\ny=${y}`);

    const target = document.elementFromPoint(x, y);
    if (!target) {
      console.log(`[SS-LIVEQUERY] elementFromPoint: null (ELEMENT_NOT_FOUND)`);
      return { status: 'ELEMENT_NOT_FOUND', x, y };
    }

    const cleanTargetText = this.getCleanText(target);
    console.log(`[SS-LIVEQUERY] elementFromPoint:\ntag=${target.tagName.toLowerCase()}\ntextPreview=${cleanTargetText.slice(0, 60)}`);

    const rect = target.getBoundingClientRect();
    const bounds = {
      x: Math.round(rect.left),
      y: Math.round(rect.top),
      width: Math.round(rect.width),
      height: Math.round(rect.height)
    };

    const type = this.getElementType(target);
    let selector = target.tagName.toLowerCase();
    if (target.id && typeof target.id === 'string') {
      selector = `#${target.id}`;
    } else if (typeof target.className === 'string' && target.className.trim()) {
      const classNames = target.className.trim().split(/\s+/).filter(Boolean);
      if (classNames.length > 0) {
        selector = `.${classNames.join('.')}`;
      }
    }

    // Containing paragraph or block-level text container
    let containingParagraph = null;
    const paragraphAncestor = target.closest('p, blockquote, li, pre, dd, dt');
    if (paragraphAncestor) {
      containingParagraph = this.getCleanText(paragraphAncestor);
    } else {
      // Look for block container div or section with reasonable text length
      let curr = target.parentElement;
      while (curr && curr !== document.body && curr !== document.documentElement) {
        const display = (typeof window !== 'undefined' && window.getComputedStyle) ? window.getComputedStyle(curr).display : '';
        if (display === 'block' || display === 'flex' || display === 'grid' || curr.tagName.toLowerCase() === 'div') {
          const txt = this.getCleanText(curr);
          if (txt.length > 0 && txt.length <= 1500) {
            containingParagraph = txt;
            break;
          }
        }
        curr = curr.parentElement;
      }
    }

    // Containing or nearest heading
    let containingHeading = null;
    const headingAncestor = target.closest('h1, h2, h3, h4, h5, h6, [role="heading"]');
    if (headingAncestor) {
      containingHeading = this.getCleanText(headingAncestor);
    }

    // Containing section
    let containingSection = null;
    const sectionAncestor = target.closest('section, article, main, nav, [role="region"], [role="article"]');
    if (sectionAncestor) {
      containingSection = this.getCleanText(sectionAncestor);
    }

    const containingText = containingParagraph || cleanTargetText;
    console.log(`[SS-LIVEQUERY] containing target:\ntype=${type}\ntextLength=${(containingText || cleanTargetText).length}`);

    return {
      status: 'OK',
      x: x,
      y: y,
      targetElement: {
        id: target.id || null,
        tag: target.tagName.toLowerCase(),
        text: cleanTargetText,
        bounds: bounds,
        type: type,
        selector: selector
      },
      containingText: containingText || cleanTargetText,
      containingParagraph: containingParagraph || cleanTargetText,
      containingHeading: containingHeading,
      containingSection: containingSection
    };
  }

  /**
   * Command-time Live Selection query: inspects window.getSelection() at command execution time.
   * Deterministically returns exact selection or NO_ACTIVE_SELECTION.
   * @returns {Object}
   */
  static getActiveSelectionDetails() {
    if (typeof window === 'undefined' || !window.getSelection) {
      return { status: 'NO_ACTIVE_SELECTION', text: '', isCollapsed: true };
    }

    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      return { status: 'NO_ACTIVE_SELECTION', text: '', isCollapsed: true };
    }

    const selectedText = sel.toString().trim();
    if (selectedText.length === 0) {
      return { status: 'NO_ACTIVE_SELECTION', text: '', isCollapsed: true };
    }

    let bounds = null;
    let containingElementId = null;
    let containingParagraph = null;
    let containingSentence = null;
    let containingText = selectedText;

    if (sel.rangeCount > 0) {
      const range = sel.getRangeAt(0);
      const rect = range.getBoundingClientRect();
      if (rect) {
        bounds = {
          x: Math.round(rect.left),
          y: Math.round(rect.top),
          width: Math.round(rect.width),
          height: Math.round(rect.height)
        };
      }

      let ancestor = range.commonAncestorContainer;
      if (ancestor && ancestor.nodeType === 3) {
        ancestor = ancestor.parentElement;
      }

      if (ancestor) {
        containingElementId = ancestor.id || null;
        const blockContainer = ancestor.closest ? ancestor.closest('p, blockquote, li, pre, dd, dt, h1, h2, h3, h4, h5, h6, article, div') : ancestor;
        const fullBlockText = blockContainer ? this.getCleanText(blockContainer) : this.getCleanText(ancestor);
        
        if (fullBlockText) {
          containingText = fullBlockText;
          containingParagraph = fullBlockText;

          // Extract containing sentence
          // Split fullBlockText into sentences preserving boundaries
          const sentenceRegex = /[^.!?]+[.!?]+|\S[^.!?]*$/g;
          const sentences = fullBlockText.match(sentenceRegex) || [fullBlockText];
          for (const s of sentences) {
            const trimmedS = s.trim();
            if (trimmedS.includes(selectedText) || selectedText.includes(trimmedS)) {
              containingSentence = trimmedS;
              break;
            }
          }
          if (!containingSentence) {
            containingSentence = selectedText;
          }
        }
      }
    }

    return {
      status: 'OK',
      text: selectedText,
      isCollapsed: false,
      bounds: bounds,
      containingElementId: containingElementId,
      containingText: containingText,
      containingSentence: containingSentence || selectedText,
      containingParagraph: containingParagraph || selectedText
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
