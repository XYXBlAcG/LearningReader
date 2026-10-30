(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderHostBridge = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function createBridge(controller, send) {
    return {
      connected: false,
      identity() { return controller.identity?.() || ''; },
      material() { return controller.material?.() || null; },
      paper(options) { return controller.paper(options); },
      prepareMaterial(value) { return controller.prepareMaterial?.(value) || value; },
      prepareSelection() { controller.material?.(); },
      search(query) { return controller.search?.(query) || []; },
      connect() { this.connected = true; this.publish(); },
      publish() { if (this.connected) send({ type: "state", state: controller.read() }); },
      dispatch(name, payload) {
        if (name !== "refreshState") controller.dispatch(name, payload);
        this.publish();
      },
    };
  }

  function install(controller) {
    const handler = window.webkit?.messageHandlers?.mathReader;
    if (!handler) return null;
    const bridge = createBridge(controller, value => handler.postMessage(value));
    window.MathReaderBridge = bridge;
    const connect = bridge.connect.bind(bridge);
    bridge.connect = () => { connect(); document.body.classList.add("native-host"); if(window.READER_NATIVE_PANELS)document.body.classList.add('native-panels'); };
    return bridge;
  }

  return { createBridge, install };
});
