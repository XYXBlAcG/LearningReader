(function (root) {
  "use strict";

  function tag(node) {
    return String(node && node.tagName || "").toUpperCase();
  }

  function isHeading(node) {
    return /^H[1-6]$/.test(tag(node));
  }

  function isReferenceHeading(node) {
    return isHeading(node) && /^参考(?:答案|解答|解析)/.test(String(node.textContent || "").trim());
  }

  function listItems(node) {
    return Array.from(node.children || []).filter((child) => tag(child) === "LI");
  }

  function questionRanges(nodes, requireReference = true) {
    const children = Array.from(nodes || []);
    const found = children.findIndex(isReferenceHeading);
    if (found < 0 && requireReference) return [];
    const referenceIndex = found < 0 ? children.length : found;
    const ranges = [];
    for (let listIndex = 0; listIndex < referenceIndex; listIndex += 1) {
      const list = children[listIndex];
      if (isHeading(list) && /^(?:第\s*\d+\s*题|\d+(?:[（(]\d+[）)])?(?:[.．、](?:\s+.*)?|\s*))$/.test(String(list.textContent || "").trim())) {
        let endIndex = listIndex + 1;
        while (endIndex < referenceIndex && !(isHeading(children[endIndex]) && tag(children[endIndex]) <= tag(list))) endIndex += 1;
        ranges.push({ listIndex, itemIndex: null, endIndex });
        listIndex = endIndex - 1;
        continue;
      }
      if (tag(list) !== "OL") continue;
      const items = listItems(list);
      if (!items.length) continue;
      let endIndex = listIndex + 1;
      while (endIndex < referenceIndex) {
        const nextTag = tag(children[endIndex]);
        if (nextTag === "OL" || nextTag === "HR" || /^H[1-6]$/.test(nextTag)) break;
        endIndex += 1;
      }
      items.forEach((_, itemIndex) => {
        const isFinalItem = itemIndex === items.length - 1;
        ranges.push({
          listIndex,
          itemIndex,
          endIndex: isFinalItem ? endIndex : listIndex + 1,
        });
      });
    }
    return ranges;
  }

  function cleanSource(value) {
    return String(value || "").replace(/\u00a0/g, " ").trim();
  }

  function sourceText(node) {
    if (!node) return "";
    const formula=node.getAttribute?.('data-math-source');
    if(formula!==null&&formula!==undefined)return formula;
    if(node.classList?.contains('math-select-anchor'))return '';
    if (tag(node) === "OL" || tag(node) === "UL") return Array.from(node.children || []).map(sourceText).join("\n");
    if (tag(node) === "BR") return "\n";
    if (!node.childNodes) return String(node.textContent || "");
    return Array.from(node.childNodes).map((child) => {
      if (child.nodeType === 3) return child.nodeValue || "";
      return sourceText(child);
    }).join("");
  }

  function questionSource(nodes, range) {
    const children = Array.from(nodes || []);
    const list = children[range.listIndex];
    const item = range.itemIndex === null ? list : listItems(list)[range.itemIndex];
    const blocks = [item];
    if (range.endIndex > range.listIndex + 1) {
      blocks.push(...children.slice(range.listIndex + 1, range.endIndex));
    }
    return blocks.map((block) => cleanSource(sourceText(block))).filter(Boolean).join("\n\n");
  }

  const SUBQUESTION = "(?:\\([a-hA-H]\\)|\\([1-9][0-9]*\\)|（[a-hA-H]）|（[1-9][0-9]*）)";

  function label(marker, breakBefore) {
    const lineBreak = breakBefore ? '<br class="subquestion-break">' : "";
    return lineBreak + '<span class="subquestion-label">' + marker + "</span>";
  }

  function formatSubquestions(markdown) {
    const atQuestionStart = new RegExp("^(\\s*\\d+\\.\\s+)(" + SUBQUESTION + ")(?=\\s|$)");
    const atLineStart = new RegExp("^(\\s*)(" + SUBQUESTION + ")(?=\\s|$)");
    const afterSeparator = new RegExp("[；;]\\s*(" + SUBQUESTION + ")(?=\\s|$)", "g");
    return String(markdown || "").split("\n").map((line) => {
      let formatted = line.replace(atQuestionStart, (_, prefix, marker) => prefix + label(marker, false));
      if (formatted === line) {
        formatted = line.replace(atLineStart, (_, prefix, marker) => prefix + label(marker, true));
      }
      return formatted.replace(afterSeparator, (_, marker) => label(marker, true));
    }).join("\n");
  }

  async function copyText(text, clipboard) {
    await clipboard.writeText(text);
  }

  function fallbackCopy(text, document) {
    const input = document.createElement("textarea");
    input.value = text;
    input.setAttribute("readonly", "");
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.appendChild(input);
    input.select();
    const copied = document.execCommand("copy");
    input.remove();
    if (!copied) throw new Error("copy failed");
  }

  function setState(button, text, state, view) {
    button.textContent = text;
    button.dataset.state = state;
    view.setTimeout(() => {
      button.textContent = "⧉";
      delete button.dataset.state;
    }, 1400);
  }

  function enhance(rootElement, enabled) {
    if (!enabled) return;
    const document = rootElement.ownerDocument;
    const view = document.defaultView;
    const children = Array.from(rootElement.children);
    rootElement.querySelectorAll(".subquestion-label").forEach((label) => {
      const paragraph = label.closest("p");
      if (paragraph && paragraph.parentElement === rootElement) {
        paragraph.classList.add("subquestion-row");
      }
    });
    questionRanges(children).forEach((range) => {
      const list = children[range.listIndex];
      const item = range.itemIndex === null ? list : listItems(list)[range.itemIndex];
      if (range.itemIndex !== null) list.classList.add("question-list");
      else item.classList.add("question-heading");
      item.classList.add("question-item");
      if (range.endIndex > range.listIndex + 1) {
        item.classList.add("question-item-with-continuation");
      }
      const source = questionSource(children, range);
      const button = document.createElement("button");
      button.type = "button";
      button.className = "question-copy";
      button.textContent = "⧉";
      button.setAttribute("aria-label", "复制完整题干和公式");
      button.addEventListener("click", async () => {
        try {
          if (view.navigator.clipboard && view.navigator.clipboard.writeText) {
            await copyText(source, view.navigator.clipboard);
          } else {
            fallbackCopy(source, document);
          }
          setState(button, "✓", "success", view);
        } catch {
          setState(button, "!", "error", view);
        }
      });
      item.insertBefore(button, item.firstChild);
    });
  }

  const api = { copyText, enhance, formatSubquestions, questionRanges, isReferenceHeading, questionSource };
  root.ReaderExerciseCopy = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof window === "undefined" ? globalThis : window);
