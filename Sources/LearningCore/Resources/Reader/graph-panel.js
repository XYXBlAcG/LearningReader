'use strict';
const graphPanel=ReaderKnowledgeGraph.createView({
  container:document.getElementById('graphCanvas'),
  empty:document.getElementById('graphEmpty'),
  incoming:document.getElementById('graphIncoming'),
  outgoing:document.getElementById('graphOutgoing'),
  mode:document.getElementById('graphMode'),
  onNavigate:node=>window.webkit.messageHandlers.graphNavigate.postMessage({kind:node.kind,path:node.path,anchor:node.anchor || ''}),
});
window.NativeGraph={async update(graph,kind,path,global){
 await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
 graphPanel.setState(graph,{kind,path},global);
 await new Promise(resolve=>requestAnimationFrame(resolve));
}};
window.addEventListener('resize',()=>graphPanel.resize());
