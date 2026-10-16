import {
  bold,
  italic,
  inlineCode,
  heading,
  bulletList,
  orderedList,
  blockquote,
  codeBlock,
  table,
  link,
  insertBlock,
} from './markdownCommands';

// A command returns a replacement span; applying it is what the component does with execCommand. This helper is
// that application, so a spec reads as "value in, value out".
const apply = (command, value, from = value.length, to = from) => {
  const result = command(value, from, to);
  return value.slice(0, result.from) + result.text + value.slice(result.to);
};

describe('inline marks', () => {
  it('wraps a selection in bold and puts the caret around the text', () => {
    const result = bold('make this loud', 5, 9);
    expect(result.text).toBe('**this**');
    expect(result.selectionStart).toBe(7);
    expect(result.selectionEnd).toBe(11);
  });

  it('unwraps when the selection already carries the marker', () => {
    expect(apply(bold, '**this**', 0, 8)).toBe('this');
  });

  it('unwraps when the markers sit just outside the selection', () => {
    expect(apply(bold, '**this**', 2, 6)).toBe('this');
  });

  it('wraps an empty selection and leaves the caret between the markers', () => {
    const result = bold('', 0, 0);
    expect(result.text).toBe('****');
    expect(result.selectionStart).toBe(2);
    expect(result.selectionEnd).toBe(2);
  });

  it('uses one asterisk for emphasis and a backtick for inline code', () => {
    expect(apply(italic, 'word', 0, 4)).toBe('*word*');
    expect(apply(inlineCode, 'word', 0, 4)).toBe('`word`');
  });
});

describe('line-oriented blocks', () => {
  it('adds a heading prefix to the line the caret is on', () => {
    expect(apply(heading(2), 'A title', 3)).toBe('## A title');
  });

  it('replaces an existing heading level rather than stacking markers', () => {
    expect(apply(heading(3), '## A title', 4)).toBe('### A title');
  });

  it('removes the prefix when every selected line already has it', () => {
    expect(apply(heading(2), '## A title', 4)).toBe('A title');
  });

  it('bullets every selected line, leaving blank lines alone', () => {
    expect(apply(bulletList, 'one\n\ntwo', 0, 8)).toBe('- one\n\n- two');
  });

  it('converts an existing bullet rather than nesting one', () => {
    expect(apply(bulletList, '* one', 0, 5)).toBe('- one');
  });

  it('numbers an ordered list from one, whatever the source said', () => {
    expect(apply(orderedList, 'one\ntwo\nthree', 0, 13)).toBe(
      '1. one\n2. two\n3. three'
    );
  });

  it('renumbers from one when the source is all 1.', () => {
    expect(apply(orderedList, '1. one\n1. two', 0, 13)).toBe('one\ntwo');
  });

  it('quotes the selected lines', () => {
    expect(apply(blockquote, 'said it', 0, 7)).toBe('> said it');
  });
});

describe('fenced blocks', () => {
  it('fences the selection and leaves the caret on the content', () => {
    const result = codeBlock()('let a = 1', 0, 9);
    expect(result.text).toBe('```\nlet a = 1\n```');
    expect(result.selectionStart).toBe(4);
  });

  // The renderer puts the info string in class="language-..." after escaping it, so the language is a real
  // field -- and it is the one thing the ProseMirror serializer drops (corpusRoundTrip.spec.js).
  it('keeps an info string when one is given', () => {
    expect(apply(codeBlock('json'), '{}', 0, 2)).toBe('```json\n{}\n```');
  });
});

describe('tables', () => {
  it('writes the delimiter row in the corpus style, not the serializer padding', () => {
    expect(apply(table(2, 1), '')).toBe(
      '| Column | Column |\n|---|---|\n|  |  |\n'
    );
  });

  it('opens a blank line when the caret is mid-line', () => {
    expect(apply(table(1, 1), 'text')).toBe(
      'text\n\n| Column |\n|---|\n|  |\n'
    );
  });
});

describe('links', () => {
  it('labels the selection and keeps the destination empty for the operator to fill', () => {
    expect(apply(link(''), 'the page', 0, 8)).toBe('[the page]()');
  });

  it('puts the caret in the label when there is nothing selected', () => {
    const result = link('work-in-the-inbox')('', 0, 0);
    expect(result.text).toBe('[](work-in-the-inbox)');
    expect(result.selectionStart).toBe(1);
  });
});

// The editor does not compose the image string; Documentation::MediaUpload#create! returns it and this inserts
// it. So what is under test is block placement, not grammar.
describe('insertBlock', () => {
  const MEDIA = '![Step two](media:uploads/8f3a1c2b5d7e9a04-step-two.png)';

  it('inserts the server-composed markdown unchanged', () => {
    expect(apply(insertBlock(MEDIA), '')).toBe(MEDIA);
  });

  it('opens a blank line before it when the caret is mid-line', () => {
    expect(apply(insertBlock(MEDIA), 'prose')).toBe(`prose\n\n${MEDIA}`);
  });

  it('closes a blank line after it when prose follows on the same line', () => {
    expect(apply(insertBlock(MEDIA), 'before after', 7, 7)).toBe(
      `before \n\n${MEDIA}\n\nafter`
    );
  });

  it('adds no blank lines when the caret already starts an empty line', () => {
    expect(apply(insertBlock(MEDIA), 'prose\n\n', 7, 7)).toBe(
      `prose\n\n${MEDIA}`
    );
  });
});
