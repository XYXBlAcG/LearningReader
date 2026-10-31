'use strict';
const graphPanel=ReaderKnowledgeGraph.createView({
  container:document.getElementById('graphCanvas'),
  empty:document.getElementById('graphEmpty'),
  incoming:document.getElementById('graphIncoming'),
  outgoing:document.getElementById('graphOutgoing'),
  mode:document.getElementById('graphMode'),
  onNavigate:node=>window.webkit.messageHandlers.graphNavigate.postMessage({kind:node.kind,path:node.path,anchor:node.anchor || ''}),
});
window.NativeGraph={update(graph,kind,path,global){graphPanel.setGlobal(global);graphPanel.setData(graph);graphPanel.showDocument(kind,path);}};
window.addEventListener('resize',()=>graphPanel.resize());
