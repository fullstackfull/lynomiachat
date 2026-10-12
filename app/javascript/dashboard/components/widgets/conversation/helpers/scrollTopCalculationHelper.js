const totalMessageHeight = (total, element) => {
  return total + element.scrollHeight;
};

export const calculateScrollTop = (
  conversationPanelHeight,
  parentHeight,
  relevantMessages
) => {
  // add up scrollHeight of a `relevantMessages`
  let combinedMessageScrollHeight = [...relevantMessages].reduce(
    totalMessageHeight,
    0
  );
  return (
    conversationPanelHeight - combinedMessageScrollHeight - parentHeight / 2
  );
};

/**
 * Every element after `element` in its parent, so a separator and everything under it are measured together.
 * @param {Element} element - the element to start after
 * @returns {Array<Element>} the following siblings, in document order
 */
const followingSiblings = element => {
  const after = [];
  let next = element.nextElementSibling;
  while (next) {
    after.push(next);
    next = next.nextElementSibling;
  }
  return after;
};

/**
 * WHICH ELEMENTS THE PANEL MUST LEAVE ON SCREEN, in priority order. `calculateScrollTop` sums their heights
 * and scrolls that far up from the bottom, so an EMPTY result means "the bottom", which is the right answer
 * when there is nothing in particular to look at.
 *
 * 1. the unread separator AND everything below it. That is what "scroll to the first unread" means: the
 *    separator has to be visible, or the agent sees new messages without seeing where they begin.
 * 2. the label suggestion, which sits below the last message.
 * 3. nothing — the bottom.
 *
 * WHY THIS IS A FUNCTION AND NOT THREE BRANCHES IN THE COMPONENT. It used to query `.message--unread`, a class
 * NOTHING in the tree renders, so the unread branch selected an empty NodeList and the panel scrolled to the
 * bottom instead. The defect was invisible precisely because the bottom is correct for every other case, and
 * it was unreachable by a test while it lived inside a 900-line component
 * (docs/product-refinement/04-inbox-modernization.md).
 * @param {Element} panel - the conversation panel
 * @returns {Array<Element>} the elements to keep visible, possibly empty
 */
export const elementsToKeepVisible = panel => {
  if (!panel) return [];

  const separator = panel.querySelector('[data-unread-separator]');
  if (separator) return [separator, ...followingSiblings(separator)];

  const labelSuggestion = panel.querySelector('.label-suggestion');
  return labelSuggestion ? [labelSuggestion] : [];
};
