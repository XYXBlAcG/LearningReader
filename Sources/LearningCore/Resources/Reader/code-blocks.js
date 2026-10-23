(function (root) {
  "use strict";

  const labels = {
    cpp: "C++",
    "c++": "C++",
    c: "C",
    python: "Python",
    py: "Python",
    javascript: "JavaScript",
    js: "JavaScript",
    typescript: "TypeScript",
    ts: "TypeScript",
    bash: "Shell",
    shell: "Shell",
    plaintext: "文本",
    text: "文本",
  };

  function languageLabel(language) {
    const key = String(language || "").toLowerCase();
    if (!key) return "代码";
    return labels[key] || key.toUpperCase();
  }

  async function copyText(text, clipboard) {
    await clipboard.writeText(text);
  }

  function declaredLanguage(code) {
    const className = [...code.classList].find((name) => name.startsWith("language-"));
    return className ? className.slice(9) : "";
  }

  function setCopyState(button, text, state, view) {
    button.textContent = text;
    button.dataset.state = state;
    view.setTimeout(() => {
      button.textContent = "复制";
      delete button.dataset.state;
    }, 1400);
  }

  function enhance(rootElement) {
    const view = rootElement.ownerDocument.defaultView;
    rootElement.querySelectorAll("pre > code").forEach((code) => {
      if (code.closest(".code-block")) return;
      const source = code.textContent;
      const declared = declaredLanguage(code);
      if (view.hljs) view.hljs.highlightElement(code);

      const wrapper = rootElement.ownerDocument.createElement("div");
      wrapper.className = "code-block";
      const toolbar = rootElement.ownerDocument.createElement("div");
      toolbar.className = "code-toolbar";
      const language = rootElement.ownerDocument.createElement("span");
      language.className = "code-language";
      language.textContent = languageLabel(declared || (code.result && code.result.language));
      const copy = rootElement.ownerDocument.createElement("button");
      copy.className = "code-copy";
      copy.type = "button";
      copy.textContent = "复制";
      copy.setAttribute("aria-label", "复制代码");
      copy.addEventListener("click", async () => {
        try {
          await copyText(source, view.navigator.clipboard);
          setCopyState(copy, "已复制", "success", view);
        } catch {
          setCopyState(copy, "复制失败", "error", view);
        }
      });

      const pre = code.parentElement;
      pre.before(wrapper);
      toolbar.append(language, copy);
      wrapper.append(toolbar, pre);
    });
  }

  const api = { copyText, enhance, languageLabel };
  root.ReaderCodeBlocks = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof window === "undefined" ? globalThis : window);
