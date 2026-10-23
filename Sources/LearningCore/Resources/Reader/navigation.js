(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderNavigation = api.ReaderNavigation;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  class ReaderNavigation {
    constructor(browser, storage, session) {
      this.browser = browser;
      this.storage = storage;
      this.session = session;
      this.records = [];
      try {
        const saved = JSON.parse(storage.getItem("reader_recent") || "[]");
        if (Array.isArray(saved)) this.records = saved.filter(item =>
          item && ["note", "exercise"].includes(item.kind) && typeof item.path === "string"
          && item.path.endsWith(".md") && Number.isFinite(item.time)).slice(0, 200);
      } catch {}
      const state = browser.state?.reader;
      this.index = state?.index ?? 0;
      this.tip = state ? Number(session.getItem("reader_navigation_tip") || this.index) : 0;
      this.current = state || null;
    }

    get canBack() { return this.index > 0; }
    get canForward() { return this.index < this.tip; }

    checkpoint(snapshot) {
      if (!this.current) return;
      this.current = { ...this.current, snapshot };
      this.browser.replaceState({ reader: this.current }, "", this.url(this.current));
      const record = this.records.find(item => item.kind === this.current.kind && item.path === this.current.path);
      if (record) {
        record.snapshot = snapshot;
        this.persist();
      }
    }

    visit(target, snapshot) {
      const entry = { ...target, anchor: target.anchor || "", snapshot, index: this.index };
      const same = this.current && this.current.kind === entry.kind && this.current.path === entry.path
        && this.current.anchor === entry.anchor;
      if (this.current && !same) entry.index++;
      if (!this.current || same) this.browser.replaceState({ reader: entry }, "", this.url(entry));
      else this.browser.pushState({ reader: entry }, "", this.url(entry));
      this.current = entry;
      this.index = entry.index;
      if (!same) this.tip = this.index;
      this.session.setItem("reader_navigation_tip", String(this.tip));
      this.remember(entry);
    }

    adopt(state) {
      if (!state?.reader) return null;
      this.current = state.reader;
      this.index = this.current.index;
      return this.current;
    }

    remember(entry) {
      const record = { kind: entry.kind, path: entry.path, anchor: entry.anchor || "",
        snapshot: entry.snapshot, time: Date.now() };
      this.records = [record, ...this.records.filter(item => item.kind !== entry.kind || item.path !== entry.path)].slice(0, 200);
      this.persist();
    }

    persist() { this.storage.setItem("reader_recent", JSON.stringify(this.records)); }
    clear() { this.records = []; this.storage.removeItem("reader_recent"); }
    url(entry) {
      const params = new URLSearchParams({ kind: entry.kind, path: entry.path });
      if (entry.anchor) params.set("anchor", entry.anchor);
      return "/reader?" + params.toString();
    }
  }

  return { ReaderNavigation };
});
