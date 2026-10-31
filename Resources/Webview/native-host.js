/* Native document protocol v1. The licensed editor bundle remains behind this adapter. */
(() => {
  "use strict";
  const version = 1;
  const channelID = window.__nativeChannelID || "standalone";
  let documentID = null;
  let revision = 0;
  let messageID = 0;
  let lastSentRevision = 0;
  let acknowledgedRevision = 0;
  let lastMarkdown = "";
  let muted = 0;
  let hasLocalEdits = false;
  let originalMarkdown = "";
  const legacy = message => window.dispatchEvent(new MessageEvent("message", { data: message }));
  const withoutEdits = action => {
    muted++;
    try { return action(); } finally { muted--; }
  };
  function post(message) {
    if (muted) return;
    if (message.type !== "ready" && !documentID) return;
    if (message.type === "edit" && !hasLocalEdits) return;
    if (message.type === "edit" && message.markdown !== lastMarkdown) {
      if (revision === lastSentRevision) revision++;
      lastMarkdown = message.markdown;
    }
    if (message.type === "edit") lastSentRevision = revision;
    window.webkit?.messageHandlers?.mdEditor?.postMessage({
      ...message, protocolVersion: version, channelID, documentID, revision, messageID: ++messageID
    });
  }
  // Compatibility is isolated here; the native host uses only the protocol below.
  window.acquireVsCodeApi = () => ({ postMessage: post, getState: () => null, setState: () => {} });
  window.__nativeEditor = {
    didEdit() {
      if (muted || !documentID) return;
      revision++;
      hasLocalEdits = true;
      post({ type: "dirty" });
    },
    state: () => ({ documentID, revision, acknowledgedRevision }),
    receive(command) {
      if (command.protocolVersion !== version || command.channelID !== channelID) throw new Error("Invalid native protocol/channel");
      if (command.type !== "load" && command.documentID !== documentID) throw new Error("Outdated document");
      switch (command.type) {
        case "load":
          if (documentID) throw new Error("A new document requires a fresh editor page");
          documentID = command.documentID;
          revision = command.revision;
          lastSentRevision = revision;
          originalMarkdown = command.markdown;
          lastMarkdown = command.markdown;
          withoutEdits(() => legacy({ type: "init", markdown: command.markdown, ...command.context, defaults: command.defaults }));
          if (!window.__mdEditorBridge?.getEditor()) throw new Error("Editor initialization failed");
          break;
        case "snapshot": {
          if (command.lock) document.body.inert = true;
          const editorMarkdown = window.__mdEditorBridge.getMarkdown(); // flush both rich and source debounces
          const markdown = hasLocalEdits ? editorMarkdown : originalMarkdown;
          if (markdown !== lastMarkdown) post({ type: "edit", markdown });
          return { protocolVersion: version, channelID, requestID: command.requestID, documentID, revision, markdown };
        }
        case "unlock": document.body.inert = false; break;
        case "context": withoutEdits(() => window.__mdEditorBridge.setContext(command.context)); break;
        case "saveState":
          withoutEdits(() => {
            legacy({ type: "saveState", state: command.state, flash: command.state === "saved" });
            if (command.state === "saved" && revision > command.revision) window.__mdEditorBridge.markUnsaved();
          });
          break;
        case "textSize": {
          const buttons = [...document.querySelectorAll("#text-seg .seg-btn")];
          const current = buttons.findIndex(button => button.classList.contains("active"));
          buttons[Math.max(0, Math.min(buttons.length - 1, current + Math.sign(command.delta)))]?.click();
          break;
        }
        case "ack": acknowledgedRevision = Math.max(acknowledgedRevision, command.revision); break;
        default: throw new Error("Unknown native command: " + command.type);
      }
      return { protocolVersion: version, channelID, requestID: command.requestID, documentID, revision };
    }
  };
})();
