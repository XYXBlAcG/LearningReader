(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderDataSource = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function encodePath(path) {
    return path.split("/").map(encodeURIComponent).join("/");
  }

  function createReaderDataSource(mode) {
    if (mode !== "api" && mode !== "static") {
      throw new Error("Unsupported reader data mode: " + mode);
    }
    return {
      filesUrl() {
        return mode === "static" ? "/content/index.json" : "/api/reader/files";
      },
      graphUrl() {
        return mode === "static" ? "/content/graph.json" : "/api/reader/graph";
      },
      searchUrl() {
        return mode === "static" ? "/content/search-index.json" : "/api/reader/search-index";
      },
      fileUrl(kind, path) {
        if (mode === "static") return "/content/" + kind + "/" + encodePath(path);
        return "/api/reader/file?kind=" + kind + "&path=" + encodeURIComponent(path);
      },
    };
  }

  return { createReaderDataSource };
});
