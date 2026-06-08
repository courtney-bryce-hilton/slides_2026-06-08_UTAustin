// research-program-viz.js
// Renders an interactive 3-node triangle inside any .triangle-graph container.
// Labels come from data-labels='["A","B","C"]' (JSON) or "A,B,C" (CSV).
(() => {
    const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

    function parseLabels(el) {
        const raw = el.dataset.labels;
        if (!raw) return ["A", "B", "C"];
        try {
            const arr = JSON.parse(raw);
            if (Array.isArray(arr) && arr.length >= 3) return arr.slice(0, 3);
        } catch (_) { }
        // CSV fallback
        const parts = raw.split(",").map(s => s.trim()).filter(Boolean);
        return (parts.concat(["A", "B", "C"])).slice(0, 3);
    }

    function parseDetails(el) {
        // Supports JSON array (recommended): ["A details", "B info", "C notes"]
        // You can put multiple callouts for a node separated by "|", e.g. "fast|robust"
        const raw = el.dataset.details;
        if (!raw) return [[], [], []];
        try {
            const arr = JSON.parse(raw);         // expect length 3
            return [0, 1, 2].map(i => String(arr[i] || "")
                .split("|").map(s => s.trim()).filter(Boolean));
        } catch {
            // Fallback: CSV "A,B,C"
            return String(raw).split(",").slice(0, 3).map(s => [s.trim()].filter(Boolean));
        }
    }

    // Place detail texts around the node, evenly spaced
    function addNodeDetails(
        gNode, center, nodeR, items,
        baseGap = 8, safety = 2, sidePerChar = 1.5, power = 3
    ) {
        if (!items || items.length === 0) return;
        const n = items.length;

        for (let k = 0; k < n; k++) {
            const theta = (-90 + (360 / Math.max(n, 1)) * k) * Math.PI / 180;
            const ux = Math.cos(theta), uy = Math.sin(theta);

            // Create at center to measure
            const t = document.createElementNS("http://www.w3.org/2000/svg", "text");
            t.setAttribute("class", "tri-detail measuring");
            t.setAttribute("x", center.x);
            t.setAttribute("y", center.y);
            t.setAttribute("text-anchor", "middle");
            t.setAttribute("dominant-baseline", "middle");

            const label = String(items[k] ?? "");
            t.textContent = label;
            gNode.appendChild(t);

            // Geometry of label
            const bbox = t.getBBox();                // accurate in user space (while .measuring)
            const hw = bbox.width / 2;
            const hh = bbox.height / 2;

            // Exact support distance of axis-aligned rect along ray (ux, uy)
            const support = Math.abs(hw * ux) + Math.abs(hh * uy);

            // Angle-aware side pad scaled by character count
            const chars = label.length;
            const sideFactor = Math.pow(Math.abs(ux), power);   // 0 at top/bottom, 1 at pure side
            const extraSide = sidePerChar * chars * sideFactor; // e.g., 0.6px per char @ side

            // Final radius so the rect clears the circle by baseGap + safety + extraSide
            const ringR = nodeR + baseGap + support + safety + extraSide;

            // Position label center
            t.setAttribute("x", center.x + ringR * ux);
            t.setAttribute("y", center.y + ringR * uy);

            // Re-enable animations
            t.classList.remove("measuring");
        }
    }

    function render(container) {
        // Clear old render
        container.innerHTML = "";

        // Size
        const { width: w, height: h } = container.getBoundingClientRect();
        if (w === 0 || h === 0) return; // will re-render on ResizeObserver

        // SVG
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        svg.setAttribute("class", "tri-svg");
        svg.setAttribute("width", "100%");
        svg.setAttribute("height", "100%");
        svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
        container.appendChild(svg);

        const cx = w / 2, cy = h / 2;
        const R = Math.min(w, h) * 0.30;
        const angles = [-90, 150, 30].map(a => a * Math.PI / 180);

        // scale X distances from center by a factor (>1 widens)
        const stretchX = 1.5;

        const pts = angles.map(theta => ({
            x: cx + stretchX * R * Math.cos(theta),
            y: cy + R * Math.sin(theta),
        }));

        // Edges
        const edgeEls = [];

        const edges = [
            [0, 1],
            [1, 2],
            [2, 0],
        ];

        edges.forEach(([i, j]) => {
            const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
            line.setAttribute("class", "tri-edge");
            line.setAttribute("x1", pts[i].x);
            line.setAttribute("y1", pts[i].y);
            line.setAttribute("x2", pts[j].x);
            line.setAttribute("y2", pts[j].y);
            // mark endpoints for logic
            line.dataset.i = String(i);
            line.dataset.j = String(j);
            svg.appendChild(line);
            edgeEls.push(line);
        });

        // Nodes
        const labels = parseLabels(container);
        const nodeR = clamp(Math.min(w, h) * 0.04, 10, 26);

        const detailsByNode = parseDetails(container);

        const nodeGs = [];

        pts.forEach((p, idx) => {
            const g = document.createElementNS("http://www.w3.org/2000/svg", "g");
            g.setAttribute("class", "tri-node");
            g.setAttribute("tabindex", "0");

            const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
            circle.setAttribute("cx", p.x);
            circle.setAttribute("cy", p.y);
            circle.setAttribute("r", nodeR);
            g.appendChild(circle);

            const text = document.createElementNS("http://www.w3.org/2000/svg", "text");
            text.setAttribute("x", p.x);
            text.setAttribute("y", p.y);
            text.setAttribute("class", "tri-label");
            text.setAttribute("text-anchor", "middle");
            text.textContent = labels[idx] ?? ["A", "B", "C"][idx];
            g.appendChild(text);

            addNodeDetails(g, { x: p.x, y: p.y }, nodeR, detailsByNode[idx]);
            svg.appendChild(g);
            nodeGs.push(g);
        });

        wireHoverDim(svg, nodeGs, edgeEls);

    }

    function initTriangleGraphs(root = document) {
        const els = Array.from(root.querySelectorAll(".triangle-graph"));
        if (els.length === 0) return;

        // Render now + on resize (handles hidden → visible slide transitions too)
        const ro = new ResizeObserver(entries => {
            for (const entry of entries) render(entry.target);
        });

        els.forEach(el => {
            // Ensure the container can grow within your slide-content box
            el.classList.add("tri-host");
            render(el);
            ro.observe(el);
        });

        // If Reveal.js is present, re-render on slide changes (sizes can change)
        if (window.Reveal && typeof window.Reveal.on === "function") {
            window.Reveal.on("slidechanged", () => els.forEach(render));
            window.Reveal.on("ready", () => els.forEach(render));
        }
    }

    function wireHoverDim(svg, nodes, edges) {
        function activate(idx) {
            svg.classList.add("dim-all");
            nodes[idx].classList.add("active");
            // edges: mark connected vs not
            edges.forEach(line => {
                const i = +line.dataset.i, j = +line.dataset.j;
                if (i === idx || j === idx) {
                    line.classList.add("edge-active");
                    line.classList.remove("edge-dim");
                } else {
                    line.classList.add("edge-dim");
                    line.classList.remove("edge-active");
                }
            });
        }
        function clear() {
            svg.classList.remove("dim-all");
            nodes.forEach(n => n.classList.remove("active"));
            edges.forEach(line => line.classList.remove("edge-active", "edge-dim"));
        }
        nodes.forEach((g, idx) => {
            g.addEventListener("mouseenter", () => activate(idx));
            g.addEventListener("mouseleave", clear);
            g.addEventListener("focus", () => activate(idx));       // keyboard
            g.addEventListener("blur", clear);
        });
    }

    // Init on DOM ready
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => initTriangleGraphs());
    } else {
        initTriangleGraphs();
    }

    // Expose for manual calls if needed
    window.initTriangleGraphs = initTriangleGraphs;
})();
