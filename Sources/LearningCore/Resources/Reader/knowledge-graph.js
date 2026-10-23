(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ReaderKnowledgeGraph = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function escapeHtml(value) {
    return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function encodeTarget(target) {
    const [path, ...anchorParts] = target.split("#");
    const withExtension = path && !path.toLowerCase().endsWith(".md") ? path + ".md" : path;
    const encodedPath = withExtension.split("/").map(encodeURIComponent).join("/");
    const anchor = anchorParts.join("#");
    return encodedPath + (anchor ? "#" + encodeURIComponent(anchor) : "");
  }

  function renderWikiLinks(source) {
    let inFence = false;
    return source.split("\n").map((line) => {
      if (/^\s*(```|~~~)/.test(line)) {
        inFence = !inFence;
        return line;
      }
      if (inFence) return line;
      return line.split(/(`[^`]*`)/g).map((part, index) => {
        if (index % 2) return part;
        return part.replace(/(?<!!)\[\[([^\]\n]+)\]\]/g, (_, body) => {
          const divider = body.indexOf("|");
          const target = (divider < 0 ? body : body.slice(0, divider)).trim();
          const label = (divider < 0 ? target.split("#").pop() : body.slice(divider + 1)).trim();
          return '<a class="wiki-link" href="' + encodeTarget(target) + '">' +
            escapeHtml(label) + "</a>";
        });
      }).join("");
    }).join("\n");
  }

  function selectNeighborhood(graph, kind, path) {
    const activeIds = new Set(
      graph.nodes.filter((node) => node.kind === kind && node.path === path).map((node) => node.id),
    );
    const visibleIds = new Set(activeIds);
    graph.edges.forEach((edge) => {
      if (activeIds.has(edge.source) || activeIds.has(edge.target)) {
        visibleIds.add(edge.source);
        visibleIds.add(edge.target);
      }
    });
    return {
      nodes: graph.nodes
        .filter((node) => visibleIds.has(node.id))
        .map((node) => ({ ...node, active: activeIds.has(node.id) })),
      edges: graph.edges.filter(
        (edge) => visibleIds.has(edge.source) && visibleIds.has(edge.target),
      ),
    };
  }

  function connectedGraph(graph) {
    const ids = new Set();
    graph.edges.forEach((edge) => {
      ids.add(edge.source);
      ids.add(edge.target);
    });
    return {
      nodes: graph.nodes.filter((node) => ids.has(node.id)).map((node) => ({ ...node })),
      edges: graph.edges.filter((edge) => ids.has(edge.source) && ids.has(edge.target)),
    };
  }

  function createView(options) {
    let graph = { nodes: [], edges: [], backlinks: {}, unresolved: [] };
    let active = null;
    let globalMode = false;
    let instance = null;

    function documentMatches(node, item) {
      return item && node.kind === item.kind && node.path === item.path;
    }

    function relationLabel(type) {
      return { prerequisite: "前置", extension: "延伸", related: "相关" }[type] || "相关";
    }

    function renderList(root, entries, emptyText) {
      root.innerHTML = "";
      if (!entries.length) {
        const empty = document.createElement("div");
        empty.className = "graph-list-empty";
        empty.textContent = emptyText;
        root.appendChild(empty);
        return;
      }
      entries.forEach(({ node, type }) => {
        const button = document.createElement("button");
        button.className = "graph-link-item";
        button.innerHTML = '<span class="graph-link-type">' + relationLabel(type) +
          '</span><span class="graph-link-label">' + escapeHtml(node.label) + "</span>";
        button.title = node.documentLabel + (node.anchor ? " · " + node.label : "");
        button.onclick = () => options.onNavigate(node);
        root.appendChild(button);
      });
    }

    function renderLists() {
      if (!active) return;
      const nodeById = new Map(graph.nodes.map((node) => [node.id, node]));
      const activeIds = new Set(
        graph.nodes.filter((node) => documentMatches(node, active)).map((node) => node.id),
      );
      const outgoing = graph.edges
        .filter((edge) => activeIds.has(edge.source) && nodeById.has(edge.target))
        .map((edge) => ({ node: nodeById.get(edge.target), type: edge.type }));
      const incoming = graph.edges
        .filter((edge) => activeIds.has(edge.target) && nodeById.has(edge.source))
        .map((edge) => ({ node: nodeById.get(edge.source), type: edge.type }));
      renderList(options.outgoing, outgoing, "本页还没有添加概念链接");
      renderList(options.incoming, incoming, "还没有其他笔记提到本页");
    }

    function renderCanvas() {
      if (instance) instance.destroy();
      const selected = globalMode ? connectedGraph(graph) : selectNeighborhood(
        graph, active ? active.kind : "note", active ? active.path : "",
      );
      selected.nodes = selected.nodes.map((node) => ({
        ...node,
        active: documentMatches(node, active) ? "yes" : "no",
      }));
      options.empty.hidden = selected.nodes.length > 0;
      options.container.hidden = selected.nodes.length === 0;
      if (!selected.nodes.length || typeof cytoscape !== "function") return;
      const elements = [
        ...selected.nodes.map((node) => ({ data: { ...node, active: node.active } })),
        ...selected.edges.map((edge, index) => ({
          data: { id: "edge-" + index, ...edge, label: relationLabel(edge.type) },
        })),
      ];
      instance = cytoscape({
        container: options.container,
        elements,
        minZoom: .45,
        maxZoom: 2.2,
        style: [
          { selector: "node", style: {
            "background-color": "#ffffff", "border-color": "#b8c2bf", "border-width": 1.5,
            label: "data(label)", color: "#303331", "font-size": 10, "font-family": "Inter",
            "text-wrap": "wrap", "text-max-width": 88, width: 35, height: 35,
            "text-valign": "bottom", "text-margin-y": 7,
            "text-background-color": "#ffffff", "text-background-opacity": .9,
            "text-background-padding": 2,
          } },
          { selector: "node[anchor != '']", style: { shape: "round-rectangle", width: 44, height: 28 } },
          { selector: "node[active = 'yes']", style: {
            "background-color": "#10a37f", "border-color": "#087d61",
            "font-weight": 600, width: 42, height: 42,
          } },
          { selector: "edge", style: {
            width: 1.2, "line-color": "#aeb8b5", "target-arrow-color": "#aeb8b5",
            "target-arrow-shape": "triangle", "curve-style": "bezier", opacity: .82,
          } },
          { selector: "edge[type = 'prerequisite']", style: {
            "line-color": "#7c8cf8", "target-arrow-color": "#7c8cf8",
          } },
          { selector: "edge[type = 'extension']", style: {
            "line-color": "#d08a45", "target-arrow-color": "#d08a45",
          } },
        ],
        layout: { name: "cose", animate: false, padding: 20, nodeRepulsion: 9000, idealEdgeLength: 85 },
      });
      instance.on("tap", "node", (event) => options.onNavigate(event.target.data()));
    }

    function render() {
      renderCanvas();
      renderLists();
      options.mode.textContent = globalMode ? "显示局部" : "显示全局";
      options.mode.setAttribute("aria-pressed", globalMode ? "true" : "false");
      if (options.onRendered) options.onRendered();
    }

    options.mode.onclick = () => {
      globalMode = !globalMode;
      render();
    };

    return {
      setData(value) {
        graph = value;
        render();
      },
      showDocument(kind, path) {
        active = { kind, path };
        render();
      },
      resize() {
        if (instance) {
          instance.resize();
          instance.layout({
            name: "cose", animate: false, padding: 20, nodeRepulsion: 9000, idealEdgeLength: 85,
          }).run();
          instance.fit(undefined, 20);
        }
      },
    };
  }

  return { createView, renderWikiLinks, selectNeighborhood };
});
