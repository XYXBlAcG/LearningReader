(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderSidebarTree = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function buildFolderTree(files) {
    const roots = [];
    const folders = new Map();
    for (const file of files) {
      const parts = file.path.split('/');
      let children = roots;
      for (let index = 1; index < parts.length - 1; index++) {
        const key = parts.slice(0, index + 1).join('/');
        if (!folders.has(key)) {
          const node = {file:null,label:parts[index],path:key,depth:index-1,children:[]};
          folders.set(key,node);
          children.push(node);
        }
        children = folders.get(key).children;
      }
      children.push({file,depth:Math.max(0,parts.length-2),children:[]});
    }
    function sort(nodes) {
      nodes.sort((a,b)=>(a.file?.path.split('/').at(-1)||a.label).localeCompare(b.file?.path.split('/').at(-1)||b.label,'zh-CN',{numeric:true}));
      nodes.forEach(node=>sort(node.children));
    }
    sort(roots);
    return roots;
  }
  function folderIsOpen(state, key, folder, activePath) {
    if (Object.prototype.hasOwnProperty.call(state, key)) return !state[key];
    return !!activePath && activePath.startsWith(folder + '/');
  }

  function setExpansion(state, keys, expanded) {
    for (const key of keys) state[key] = !expanded;
  }

  return { buildFolderTree, folderIsOpen, setExpansion };
});
