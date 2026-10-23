(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderHostBridge = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function createBridge(controller, send) {
    return {
      connected: false,
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
    bridge.connect = () => { connect(); document.body.classList.add("native-host"); };
    return bridge;
  }

  return { createBridge, install };
});
