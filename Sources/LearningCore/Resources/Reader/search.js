(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderSearch = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function normalize(value) {
    return String(value || "").normalize("NFKC").toLowerCase();
  }

  function compact(value) {
    return normalize(value).replace(/\s+/g, "");
  }

  function conceptHeading(value) {
    return compact(value).replace(/^\d+(?:\.\d+)*[.、_-]*/, "");
  }

  function snippetFor(section, terms, phrase) {
    const source = section.text || section.heading || section.documentLabel;
    const normalized = normalize(source);
    let index = normalized.indexOf(phrase);
    if (index < 0) {
      index = terms.map((term) => normalized.indexOf(term)).find((position) => position >= 0) ?? 0;
    }
    const start = Math.max(0, index - 28);
    const end = Math.min(source.length, index + Math.max(phrase.length, 12) + 52);
    return (start ? "…" : "") + source.slice(start, end) + (end < source.length ? "…" : "");
  }

  function scoreSection(section, phrase, terms) {
    const heading = normalize(section.heading);
    const headingConcept = conceptHeading(section.heading);
    const documentLabel = normalize(section.documentLabel);
    const text = normalize(section.text);
    const combined = compact([section.heading, section.documentLabel, section.text].join(" "));
    if (!terms.every((term) => combined.includes(compact(term)))) return -1;
    let score = section.kind === "note" ? 30 : 0;
    if (headingConcept === compact(phrase)) score += 1200;
    else if (headingConcept.includes(compact(phrase))) score += 900;
    else if (compact(phrase).includes(headingConcept)) score += 760;
    if (compact(documentLabel) === compact(phrase)) score += 700;
    else if (documentLabel.includes(phrase)) score += 460;
    if (heading.includes(phrase)) score += 360;
    if (text.includes(phrase)) score += 240;
    score += terms.reduce((total, term) => {
      if (heading.includes(term)) return total + 90;
      if (documentLabel.includes(term)) return total + 55;
      return total + 15;
    }, 0);
    score -= Math.min(80, Math.floor((section.text || "").length / 300));
    return score;
  }

  function searchSections(sections, query, limit = 40) {
    const phrase = normalize(query).trim();
    if (!phrase) return [];
    const terms = phrase.split(/\s+/).filter(Boolean);
    return sections
      .map((section, order) => ({
        ...section,
        order,
        score: scoreSection(section, phrase, terms),
        snippet: snippetFor(section, terms, phrase),
      }))
      .filter((section) => section.score >= 0)
      .sort((left, right) => right.score - left.score || left.order - right.order)
      .slice(0, limit);
  }

  return { searchSections };
});
