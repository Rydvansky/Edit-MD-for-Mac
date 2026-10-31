# DEMO File - as;dlfkjas; dfkjas; ld

## Heading Level 2 - De Finibus Bonorum

### Heading Level 3 - Et Malorum

#### Heading Level 4 - Cicero Dixit

##### Heading Level 5 - Disputatio

###### Heading Level 6 - Minima

---

## Paragraphs & Line Breaks

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

First line with two trailing spaces -&gt;\
Second line starts here as a line break, not a new paragraph.

---

## Text Emphasis

Lorem ipsum **bold text** dolor sit amet, *italic text* consectetur adipiscing elit.

***Bold and italic together*** - sed do eiusmod tempor.

~~Strikethrough~~ - ullamco laboris nisi ut aliquip.

This is `inline code` inside a sentence - ex ea commodo consequat.

> **Tip:** You can combine **bold** with `code` and *italic* in the same line.

---

## Blockquotes

> Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

> Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
>
> - Marcus Tullius Cicero, probably not, but it sounds respectable.

### Nested Blockquotes

> First quote level - Lorem ipsum dolor sit amet.
>
> > Second level - consectetur adipiscing elit, sed do eiusmod tempor.
> >
> > > Third level - ut labore et dolore magna aliqua enim ad minim veniam.

---

## Lists

### Unordered List

- Lorem ipsum dolor sit amet
- Consectetur adipiscing elit
- Sed do eiusmod tempor incididunt
  - Nested item - ut labore et dolore
  - Nested item - magna aliqua enim
    - Deep nested - quis nostrud exercitation
    - Deep nested - ullamco laboris nisi
- Ut aliquip ex ea commodo consequat

### Ordered List

1. Lorem ipsum dolor sit amet
2. Consectetur adipiscing elit
3. Sed do eiusmod tempor incididunt
   1. Nested ordered - ut labore
   2. Nested ordered - et dolore magna
4. Duis aute irure dolor in reprehenderit
5. Excepteur sint occaecat cupidatat

### Task List (Checkbox)

- [x] Lorem ipsum dolor sit amet - completed

- [x] Consectetur adipiscing elit - done

- [ ] Sed do eiusmod tempor - not started

- [ ] Ut labore et dolore magna aliqua - in progress

- [x] Quis nostrud exercitation - verified

### Mixed List

1. First item
   - Sub-item A - lorem ipsum
   - Sub-item B - dolor sit amet
2. Second item
   - [ ] Unfinished task

   - [x] Finished task

---

## Code

### Inline Code

Use `const x = 42` or `npm install` inside regular text.

### Code Block (no language)

```
Lorem ipsum function() {
  return "dolor sit amet";
}
```

### Code Block - JavaScript

```javascript
// Lorem ipsum generator
function loremIpsum(words = 5) {
  const bank = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur"];
  return Array.from({ length: words }, () =>
    bank[Math.floor(Math.random() * bank.length)]
  ).join(" ");
}

console.log(loremIpsum(10));
```

### Code Block - CSS

```css
/* Lorem ipsum styles */
.lorem-container {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  font-family: "Inter", sans-serif;
  color: #1a1a1a;
}

.ipsum-text {
  font-size: 1rem;
  line-height: 1.6;
  max-width: 65ch;
}
```

### Code Block - JSON

```json
{
  "title": "Lorem Ipsum",
  "version": "1.0.0",
  "description": "Dolor sit amet consectetur",
  "tags": ["lorem", "ipsum", "dolor"],
  "meta": {
    "author": "Cicero",
    "year": 45
  }
}
```

---

## Tables

### Table Text Size

This paragraph uses the standard editor text size. The table text should match it.

| Standard text size | Example |
| -------------------- | --------- |
| Same as this line | Inherited |

### Basic Table

| Column A | Column B | Column C |
| --------------- | -------------------- | --------------- |
| Lorem ipsum | Dolor sit amet | Consectetur |
| Adipiscing | Elit sed do | Eiusmod |
| Tempor | Incididunt ut | Labore |

### Aligned Table

Markdown alignment markers remain in the source, but the app keeps cell text at the top left.

| Left-aligned | Center-aligned | Right-aligned |
| -------------- | ------------------ | ------------- |
| Lorem | Ipsum | Dolor |
| Sit amet | Consectetur | Adipiscing |
| Elit | Sed do eiusmod | Tempor |
| 100 | 250 | 1,430 |

### Table with Formatting Inside

| Feature | Status | Notes |
| --------------- | -------------------- | ------------------------- |
| **Bold** | Supported | Use `**text**` |
| *Italic* | Supported | Use `*text*` |
| `Inline code` | Supported | Use backticks |
| ~~Strike~~ | Partial | Not all renderers |
| Images | Supported | `![alt](url)` |

### Wrapping Table

| Item | Owner | Details |
| ------ | ------- | --------- |
| Preview table cells | Product review | This cell intentionally contains a long sentence so the preview can show the full content by wrapping it across multiple lines instead of clipping the text. |
| Narrow visible window | QA | Resize the app window or hide the editor pane to confirm that row height grows while the table keeps fitting inside the preview width. |
| Markdown formatting | Engineering | Long cells should still render **bold text**, *italic text*, and `inline code` while preserving readable spacing and selection. |

### Dense Wide Table

| Phase | Goal | Risk | Decision | Notes |
| ------ | ----- | ----- | --------- | ------ |
| Discovery | Confirm how table layout behaves when several columns compete for the same visible width. | Very long text can create tall rows, which is expected for full-content display. | Keep wrapping enabled. | This row is deliberately wordy to test whether every column expands vertically without hiding content. |
| Implementation | Remove fixed maximum cell width and make columns share the available preview width. | Columns become narrower when there are many of them. | Prefer complete content over horizontal scrolling. | The table should stay within the visible preview instead of forcing a sideways scroll. |
| Verification | Check left, center, and right alignment with wrapped text. | Alignment can look odd if the column is extremely narrow. | Preserve Markdown alignment markers. | Use this table as a quick regression check after layout changes. |

---

## Links & Images

### Links

[Lorem ipsum - Wikipedia](https://en.wikipedia.org/wiki/Lorem_ipsum)

[Link with title](https://example.com)

Autolink: <https://example.com>

Reference links: [Lorem](https://example.com/lorem) and [Ipsum](https://example.com/ipsum) inside text.

### Images

![Lorem ipsum placeholder](https://placehold.co/600x200?text=Lorem+Ipsum)Image inside a link:

![Lorem Badge](https://placehold.co/120x40?text=Badge)---

## Horizontal Rules

Three variants, same result:

---

---

---

---

## Footnotes

Lorem ipsum dolor sit amet\[^1\], consectetur adipiscing elit\[^2\]. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

\[^1\]: First footnote - the phrase comes from Cicero's "De Finibus Bonorum et Malorum", written in 45 BC. \[^2\]: Second footnote - the text became popular in the 1960s through Letraset transfer sheets.

---

## Definition List *(Extended Markdown)*

Lorem ipsum : Standard placeholder text used in design and publishing.

Dolor sit amet : A phrase from Latin-style placeholder text with no specific meaning here.

---

## Escaping Special Characters

To show Markdown characters literally:

\*not italic\* - \*\*not bold\*\* - \`not code\` - # not a heading

---

## HTML Inline *(where supported)*

<mark>Highlighted text through HTML mark</mark> - lorem ipsum dolor.

Subscript and Superscript - sit amet consectetur.

Ctrl + C - keyboard shortcut through `kbd`.

---

## Emoji

Some renderers support emoji through shortcodes:

:white_check_mark: Complete - :warning: Warning - :bulb: Idea - :fire: Important

Or directly: ✅ ⚠️ 💡 🔥 📌 🚀 🎯

---

## Summary / Details *(HTML in Markdown)*

<details>
<summary>Expand - Lorem ipsum hidden section</summary>

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.const hidden = "Here is hidden code!";

</details>

---

*End of document - lorem ipsum dolor sit amet, consectetur adipiscing elit. Omnia enim dicta sunt.*