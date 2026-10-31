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
  let comparison=null;
  const baselineStates=new Map(), snapshots=new Map();
  const activeState=()=>window.__mdEditorBridge?.activeState?.();
  function rememberClean(state=activeState()) { if(state)baselineStates.set(state.mode,state.signature); }
  function isClean() { const state=activeState();return !hasLocalEdits || (state && baselineStates.get(state.mode)===state.signature); }
  function capture() {
    const editorMarkdown=window.__mdEditorBridge.getMarkdown();
    const markdown=isClean()?originalMarkdown:editorMarkdown;
    if(markdown!==lastMarkdown||revision>lastSentRevision)post({type:"edit",markdown});
    snapshots.set(revision,{markdown,state:activeState()});
    if(snapshots.size>64)snapshots.delete(snapshots.keys().next().value);
    return markdown;
  }
  const legacy = message => window.dispatchEvent(new MessageEvent("message", { data: message }));
  const withoutEdits = action => {
    muted++;
    try { return action(); } finally { muted--; }
  };
  function post(message) {
    if (muted) return;
    if (message.type !== "ready" && !documentID) return;
    if (message.type === "edit" && !hasLocalEdits) return;
    if (message.type === "edit" && isClean()) message={...message,markdown:originalMarkdown};
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
      comparison?.scheduleLocal();
    },
    conversionError(message) { post({type:"conversionError",message}); },
    beginModeChange() {
      const clean=isClean();muted++;
      return ()=>{muted--;if(clean)rememberClean();comparison?.scheduleLocal();};
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
          rememberClean();
          comparison=new window.ExternalComparison(post,()=>revision);
          break;
        case "snapshot": {
          const wasInert=document.body.inert;
          if (command.lock) document.body.inert = true;
          try {
            const markdown=capture();
            return { protocolVersion: version, channelID, requestID: command.requestID, documentID, revision, markdown };
          } catch(error) {
            // Failed close/save preparation must not leave keyboard input inert.
            document.body.inert=wasInert;
            throw error;
          }
        }
        case "baseline": {
          originalMarkdown=command.markdown;
          const snapshot=snapshots.get(command.revision);
          baselineStates.clear();
          if(snapshot?.state)rememberClean(snapshot.state);
          if(command.revision===revision)rememberClean();
          break;
        }
        case "comparison": comparison.show(command);break;
        case "clearComparison": comparison.clear();break;
        case "replace": {
          if(command.expectedRevision!==undefined && (command.expectedRevision!==revision || !isClean())) throw new Error("User edits arrived before disk refresh");
          withoutEdits(()=>window.__mdEditorBridge.replaceNativeContent(command.markdown));
          revision++;lastSentRevision=revision;originalMarkdown=command.markdown;lastMarkdown=command.markdown;
          hasLocalEdits=false;baselineStates.clear();rememberClean();
          snapshots.set(revision,{markdown:command.markdown,state:activeState()});
          return {protocolVersion:version,channelID,requestID:command.requestID,documentID,revision,markdown:command.markdown};
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
