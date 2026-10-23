(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderPinnedFiles = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function documentKey(kind, path) {
    return kind + ":" + path;
  }

  function validKey(value) {
    return typeof value === "string" && /^(?:note|exercise):.+\.md$/.test(value);
  }

  function parsePinned(serialized) {
    try {
      const values = JSON.parse(serialized || "[]");
      if (!Array.isArray(values)) return [];
      return [...new Set(values.filter(validKey))];
    } catch {
      return [];
    }
  }

  function togglePinned(keys, key) {
    if (keys.includes(key)) return keys.filter((value) => value !== key);
    return [key, ...keys];
  }

  function resolvePinned(keys, files) {
    const available = new Map();
    files.notes.forEach((file) => available.set(documentKey("note", file.path), { kind: "note", file }));
    files.exercises.forEach((file) => available.set(documentKey("exercise", file.path), { kind: "exercise", file }));
    return keys.map((key) => available.get(key)).filter(Boolean);
  }

  return { documentKey, parsePinned, togglePinned, resolvePinned };
});
