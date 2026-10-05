// Patou regex pattern builder (docs/src/regex-builder.md).
//
// Builds a regex visually as a tree of nodes and renders it back out to a
// plain POSIX ERE string: the same syntax both `patou check` (Rust `regex`
// crate) and the installed shell hooks (`grep -E`) read from a single
// `.patou/config.toml` pattern. See docs/src/hooks.md for why the two have
// to agree on one byte-for-byte pattern. Deliberately does NOT expose
// PCRE-only syntax (non-capturing groups, lazy quantifiers, lookaround,
// inline flags) that `grep -E` can't evaluate - every pattern this UI can
// produce is meant to be safe to paste into all three `[commit]`/
// `[branch]`/`[tag]` sections.

(function () {
  "use strict";

  // Deliberately plain ranges, not POSIX named classes ("[:alpha:]"):
  // named classes are valid ERE/Rust-regex syntax, but JavaScript's own
  // RegExp (used for the in-page "Try it" live tester) doesn't understand
  // them at all - a bracket expression built from them would silently
  // test wrong in the browser while still being "correct" ERE. Plain
  // ranges render identically in grep -E, the Rust `regex` crate, and
  // JavaScript, so the live tester and the pattern you copy out always
  // agree.
  const POSIX_CLASSES = [
    { value: "alpha", label: "letters (a-z, A-Z)", kind: "range", chars: "a-zA-Z" },
    { value: "digit", label: "digits (0-9)", kind: "range", chars: "0-9" },
    { value: "alnum", label: "letters + digits", kind: "range", chars: "a-zA-Z0-9" },
    { value: "lower", label: "lowercase letters", kind: "range", chars: "a-z" },
    { value: "upper", label: "uppercase letters", kind: "range", chars: "A-Z" },
    { value: "space", label: "whitespace (space)", kind: "chars", chars: " " },
    { value: "punct", label: "punctuation", kind: "chars", chars: "!\"#$%&'()*+,./:;<=>?@[_`{|}~-^]\\" },
  ];

  // Builds the inside of a bracket expression (the part between `[`/`[^`
  // and the closing `]`) from a bag of individual characters, placing the
  // three positionally-special ones exactly where POSIX ERE, the Rust
  // `regex` crate, and JavaScript RegExp all agree they're literal rather
  // than special: `]` first, `^` anywhere but first, `-` last. This mirrors
  // the convention Patou's own default patterns already use (e.g.
  // `[a-z0-9-]`) instead of escaping them, since backslash has no defined
  // meaning inside POSIX bracket expressions to begin with.
  function bucketBracketChars(raw) {
    let hasCloseBracket = false;
    let hasCaret = false;
    let hasHyphen = false;
    let rest = "";
    for (const ch of raw) {
      if (ch === "]") hasCloseBracket = true;
      else if (ch === "^") hasCaret = true;
      else if (ch === "-") hasHyphen = true;
      else rest += ch;
    }
    return (hasCloseBracket ? "]" : "") + rest + (hasCaret ? "^" : "") + (hasHyphen ? "-" : "");
  }

  // Escapes a literal so it matches itself in both ERE engines.
  function escapeLiteral(raw) {
    return raw.replace(/[.^$*+?()[\]{}|\\]/g, "\\$&");
  }

  let uid = 0;
  function nextId() {
    uid += 1;
    return "n" + uid;
  }

  function makeSequence(nodes) {
    return { nodes: nodes || [] };
  }

  function defaultNode(type) {
    switch (type) {
      case "literal":
        return { id: nextId(), type: "literal", text: "text", raw: false, quant: null };
      case "charclass":
        return {
          id: nextId(),
          type: "charclass",
          negate: false,
          presets: ["alnum"],
          extra: "-_",
          quant: { kind: "plus" },
        };
      case "wildcard":
        return { id: nextId(), type: "wildcard", quant: null };
      case "anchor":
        return { id: nextId(), type: "anchor", kind: "start" };
      case "group":
        return {
          id: nextId(),
          type: "group",
          alternatives: [makeSequence([defaultNode("literal")])],
          quant: null,
        };
      case "raw":
        return { id: nextId(), type: "raw", text: "", quant: null };
      default:
        throw new Error("unknown node type: " + type);
    }
  }

  const QUANT_OPTIONS = [
    { kind: "none", label: "once" },
    { kind: "optional", label: "optional (?)" },
    { kind: "star", label: "0 or more (*)" },
    { kind: "plus", label: "1 or more (+)" },
    { kind: "exact", label: "exactly {n}" },
    { kind: "atleast", label: "at least {n,}" },
    { kind: "range", label: "between {n,m}" },
  ];

  function quantToSuffix(q) {
    if (!q || q.kind === "none") return "";
    switch (q.kind) {
      case "optional":
        return "?";
      case "star":
        return "*";
      case "plus":
        return "+";
      case "exact":
        return "{" + (q.n ?? 1) + "}";
      case "atleast":
        return "{" + (q.n ?? 1) + ",}";
      case "range":
        return "{" + (q.n ?? 1) + "," + (q.m ?? 2) + "}";
      default:
        return "";
    }
  }

  function renderNodeRegex(node) {
    let body;
    switch (node.type) {
      case "literal": {
        const text = node.text || "";
        body = node.raw ? text : escapeLiteral(text);
        // A multi-character literal needs grouping before a quantifier
        // can apply to the whole run rather than just its last char.
        if (quantToSuffix(node.quant) && [...body].length > 1) {
          body = "(" + body + ")";
        }
        break;
      }
      case "charclass": {
        let rangeBits = "";
        let charBag = node.extra || "";
        for (const def of POSIX_CLASSES) {
          if (!node.presets.includes(def.value)) continue;
          if (def.kind === "range") rangeBits += def.chars;
          else charBag += def.chars;
        }
        const inner = rangeBits + bucketBracketChars(charBag);
        body = "[" + (node.negate ? "^" : "") + inner + "]";
        break;
      }
      case "wildcard":
        body = ".";
        break;
      case "anchor":
        body = node.kind === "start" ? "^" : node.kind === "end" ? "$" : node.kind === "word" ? "\\b" : "\\B";
        break;
      case "group": {
        const alts = node.alternatives.map(renderSequenceRegex).join("|");
        body = "(" + alts + ")";
        break;
      }
      case "raw":
        body = node.text || "";
        break;
      default:
        body = "";
    }
    if (node.type !== "anchor") {
      body += quantToSuffix(node.quant);
    }
    return body;
  }

  function renderSequenceRegex(seq) {
    return seq.nodes.map(renderNodeRegex).join("");
  }

  // ---- State -----------------------------------------------------------

  function defaultState() {
    return {
      section: "commit",
      anchorStart: true,
      anchorEnd: true,
      root: makeSequence([
        (() => {
          const g = defaultNode("group");
          g.alternatives = [
            makeSequence([
              (() => {
                const c = defaultNode("charclass");
                c.presets = ["lower"];
                c.extra = "";
                c.quant = { kind: "plus" };
                return c;
              })(),
            ]),
          ];
          return g;
        })(),
      ]),
    };
  }

  const PRESETS = {
    "conventional-commit": () => {
      const typeGroup = defaultNode("group");
      typeGroup.alternatives = [
        "feat",
        "fix",
        "docs",
        "style",
        "refactor",
        "perf",
        "test",
        "build",
        "ci",
        "chore",
        "revert",
      ].map((t) => makeSequence([{ id: nextId(), type: "literal", text: t, raw: false, quant: null }]));

      const scopeInner = defaultNode("charclass");
      scopeInner.presets = ["lower", "digit"];
      scopeInner.extra = "-";
      scopeInner.quant = { kind: "plus" };
      const scopeGroup = defaultNode("group");
      scopeGroup.quant = { kind: "optional" };
      scopeGroup.alternatives = [
        makeSequence([
          { id: nextId(), type: "literal", text: "(", raw: false, quant: null },
          scopeInner,
          { id: nextId(), type: "literal", text: ")", raw: false, quant: null },
        ]),
      ];

      const colonSpace = { id: nextId(), type: "literal", text: ": ", raw: false, quant: null };

      const subjectDot = defaultNode("wildcard");
      subjectDot.quant = { kind: "range", n: 1, m: 72 };

      return {
        section: "commit",
        anchorStart: true,
        anchorEnd: true,
        root: makeSequence([typeGroup, scopeGroup, colonSpace, subjectDot]),
      };
    },
    "branch-naming": () => {
      const longLived = ["main", "develop", "dev"].map((t) =>
        makeSequence([{ id: nextId(), type: "literal", text: t, raw: false, quant: null }])
      );

      const typeGroup = defaultNode("group");
      typeGroup.alternatives = ["feature", "fix", "hotfix", "refactor", "chore", "docs"].map((t) =>
        makeSequence([{ id: nextId(), type: "literal", text: t, raw: false, quant: null }])
      );

      const descClass = defaultNode("charclass");
      descClass.presets = ["alnum"];
      descClass.extra = "._/-";
      descClass.quant = { kind: "plus" };

      const topGroup = defaultNode("group");
      topGroup.alternatives = longLived.concat([
        makeSequence([
          typeGroup,
          { id: nextId(), type: "literal", text: "/", raw: true, quant: null },
          descClass,
        ]),
      ]);

      return { section: "branch", anchorStart: true, anchorEnd: true, root: makeSequence([topGroup]) };
    },
    "semver-tag": () => {
      const num = defaultNode("charclass");
      num.presets = ["digit"];
      num.extra = "";
      num.quant = { kind: "plus" };

      const dot = { id: nextId(), type: "literal", text: ".", raw: false, quant: null };

      const semver = makeSequence([
        { id: nextId(), type: "literal", text: "v", raw: false, quant: null },
        num,
        dot,
        { ...num, id: nextId() },
        dot,
        { ...num, id: nextId() },
      ]);

      const typeGroup = defaultNode("group");
      typeGroup.alternatives = ["build", "deploy", "release"].map((t) =>
        makeSequence([{ id: nextId(), type: "literal", text: t, raw: false, quant: null }])
      );
      const descClass = defaultNode("charclass");
      descClass.presets = ["alnum"];
      descClass.extra = "._/-";
      descClass.quant = { kind: "plus" };

      const topGroup = defaultNode("group");
      topGroup.alternatives = [
        semver,
        makeSequence([typeGroup, { id: nextId(), type: "literal", text: "/", raw: true, quant: null }, descClass]),
      ];

      return { section: "tag", anchorStart: true, anchorEnd: true, root: makeSequence([topGroup]) };
    },
  };

  // ---- Rendering ---------------------------------------------------------

  function h(tag, attrs, children) {
    const el = document.createElement(tag);
    if (attrs) {
      for (const [k, v] of Object.entries(attrs)) {
        if (k === "class") el.className = v;
        else if (k === "text") el.textContent = v;
        else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2), v);
        else el.setAttribute(k, v);
      }
    }
    (children || []).forEach((c) => c && el.appendChild(c));
    return el;
  }

  function App(root) {
    let state = defaultState();
    let testValue = "";

    function render() {
      root.innerHTML = "";
      root.appendChild(buildToolbar());
      root.appendChild(buildCanvas());
      root.appendChild(buildOutput());
    }

    function buildToolbar() {
      const presetSelect = h("select", {
        class: "prb-select",
        onchange: (e) => {
          const fn = PRESETS[e.target.value];
          if (fn) {
            state = fn();
            render();
          }
          e.target.value = "";
        },
      });
      presetSelect.appendChild(h("option", { value: "", text: "Load a Patou default…" }));
      presetSelect.appendChild(h("option", { value: "conventional-commit", text: "[commit] Conventional Commits" }));
      presetSelect.appendChild(h("option", { value: "branch-naming", text: "[branch] type/description" }));
      presetSelect.appendChild(h("option", { value: "semver-tag", text: "[tag] semver + type/description" }));

      const addButtons = ["literal", "charclass", "wildcard", "anchor", "group", "raw"].map((type) =>
        h("button", {
          class: "prb-btn prb-btn-add",
          type: "button",
          text: "+ " + labelForType(type),
          onclick: () => {
            state.root.nodes.push(defaultNode(type));
            render();
          },
        })
      );

      const resetBtn = h("button", {
        class: "prb-btn prb-btn-ghost",
        type: "button",
        text: "Reset",
        onclick: () => {
          state = defaultState();
          render();
        },
      });

      return h("div", { class: "prb-toolbar" }, [
        h("div", { class: "prb-toolbar-row" }, [presetSelect, resetBtn]),
        h("div", { class: "prb-toolbar-row prb-toolbar-add" }, addButtons),
      ]);
    }

    function labelForType(type) {
      return (
        {
          literal: "Text",
          charclass: "Character set",
          wildcard: "Any char",
          anchor: "Anchor",
          group: "Group",
          raw: "Raw regex",
        }[type] || type
      );
    }

    function buildCanvas() {
      const anchorStartBox = h("label", { class: "prb-anchor-toggle" }, [
        h("input", {
          type: "checkbox",
          ...(state.anchorStart ? { checked: "checked" } : {}),
          onchange: (e) => {
            state.anchorStart = e.target.checked;
            render();
          },
        }),
        h("span", { text: "^ start of string" }),
      ]);
      const anchorEndBox = h("label", { class: "prb-anchor-toggle" }, [
        h("input", {
          type: "checkbox",
          ...(state.anchorEnd ? { checked: "checked" } : {}),
          onchange: (e) => {
            state.anchorEnd = e.target.checked;
            render();
          },
        }),
        h("span", { text: "$ end of string" }),
      ]);

      const seqEl = renderSequence(state.root, {
        remove: (idx) => {
          state.root.nodes.splice(idx, 1);
          render();
        },
        move: (idx, dir) => {
          const j = idx + dir;
          if (j < 0 || j >= state.root.nodes.length) return;
          const [n] = state.root.nodes.splice(idx, 1);
          state.root.nodes.splice(j, 0, n);
          render();
        },
      });

      return h("div", { class: "prb-canvas" }, [
        h("div", { class: "prb-anchors" }, [anchorStartBox, h("div", { class: "prb-seq-wrap" }, [seqEl]), anchorEndBox]),
      ]);
    }

    function renderSequence(seq, ctx) {
      const wrap = h("div", { class: "prb-sequence" });
      if (seq.nodes.length === 0) {
        wrap.appendChild(h("div", { class: "prb-empty", text: "(empty — matches nothing extra here)" }));
      }
      seq.nodes.forEach((node, idx) => {
        wrap.appendChild(
          renderNode(node, idx, seq.nodes.length, {
            remove: () => ctx.remove(idx),
            moveLeft: () => ctx.move(idx, -1),
            moveRight: () => ctx.move(idx, 1),
            update: render,
          })
        );
      });
      return wrap;
    }

    function quantControl(node) {
      const kind = node.quant ? node.quant.kind : "none";
      const select = h("select", {
        class: "prb-select prb-select-sm",
        onchange: (e) => {
          const k = e.target.value;
          node.quant = k === "none" ? null : { kind: k, n: 1, m: 2 };
          render();
        },
      });
      QUANT_OPTIONS.forEach((opt) => {
        const o = h("option", { value: opt.kind, text: opt.label });
        if (opt.kind === kind) o.setAttribute("selected", "selected");
        select.appendChild(o);
      });
      const children = [select];
      if (node.quant && (node.quant.kind === "exact" || node.quant.kind === "atleast" || node.quant.kind === "range")) {
        children.push(
          h("input", {
            class: "prb-input prb-input-num",
            type: "number",
            min: "0",
            value: String(node.quant.n ?? 1),
            oninput: (e) => {
              node.quant.n = Math.max(0, parseInt(e.target.value || "0", 10));
              renderOutputOnly();
            },
            onchange: render,
          })
        );
      }
      if (node.quant && node.quant.kind === "range") {
        children.push(h("span", { text: "–" }));
        children.push(
          h("input", {
            class: "prb-input prb-input-num",
            type: "number",
            min: "0",
            value: String(node.quant.m ?? 2),
            oninput: (e) => {
              node.quant.m = Math.max(0, parseInt(e.target.value || "0", 10));
              renderOutputOnly();
            },
            onchange: render,
          })
        );
      }
      return h("div", { class: "prb-quant" }, children);
    }

    function cardShell(node, idx, count, ctx, title, body) {
      return h("div", { class: "prb-card", "data-type": node.type }, [
        h("div", { class: "prb-card-head" }, [
          h("span", { class: "prb-card-title", text: title }),
          h("div", { class: "prb-card-move" }, [
            h("button", {
              class: "prb-icon-btn",
              type: "button",
              text: "←",
              disabled: idx === 0 ? "disabled" : null,
              onclick: ctx.moveLeft,
            }),
            h("button", {
              class: "prb-icon-btn",
              type: "button",
              text: "→",
              disabled: idx === count - 1 ? "disabled" : null,
              onclick: ctx.moveRight,
            }),
            h("button", { class: "prb-icon-btn prb-icon-btn-danger", type: "button", text: "✕", onclick: ctx.remove }),
          ]),
        ]),
        h("div", { class: "prb-card-body" }, body),
        node.type !== "anchor" ? quantControl(node) : null,
      ]);
    }

    function renderNode(node, idx, count, ctx) {
      switch (node.type) {
        case "literal":
          return cardShell(node, idx, count, ctx, "Text", [
            h("input", {
              class: "prb-input",
              type: "text",
              value: node.text,
              oninput: (e) => {
                node.text = e.target.value;
                renderOutputOnly();
              },
              onchange: render,
            }),
            h("label", { class: "prb-inline-check" }, [
              h("input", {
                type: "checkbox",
                ...(node.raw ? { checked: "checked" } : {}),
                onchange: (e) => {
                  node.raw = e.target.checked;
                  render();
                },
              }),
              h("span", { text: "treat as raw regex (no escaping)" }),
            ]),
          ]);

        case "charclass": {
          const checks = POSIX_CLASSES.map((c) =>
            h("label", { class: "prb-inline-check" }, [
              h("input", {
                type: "checkbox",
                ...(node.presets.includes(c.value) ? { checked: "checked" } : {}),
                onchange: (e) => {
                  if (e.target.checked) node.presets.push(c.value);
                  else node.presets = node.presets.filter((p) => p !== c.value);
                  render();
                },
              }),
              h("span", { text: c.label }),
            ])
          );
          return cardShell(node, idx, count, ctx, "Character set", [
            h("div", { class: "prb-charclass-grid" }, checks),
            h("label", { class: "prb-field-label", text: "extra literal characters" }),
            h("input", {
              class: "prb-input",
              type: "text",
              value: node.extra,
              placeholder: "e.g. -_.",
              oninput: (e) => {
                node.extra = e.target.value;
                renderOutputOnly();
              },
              onchange: render,
            }),
            h("label", { class: "prb-inline-check" }, [
              h("input", {
                type: "checkbox",
                ...(node.negate ? { checked: "checked" } : {}),
                onchange: (e) => {
                  node.negate = e.target.checked;
                  render();
                },
              }),
              h("span", { text: "negate (match anything NOT in this set)" }),
            ]),
          ]);
        }

        case "wildcard":
          return cardShell(node, idx, count, ctx, "Any character", [
            h("p", { class: "prb-hint", text: "Matches any single character ( . )." }),
          ]);

        case "anchor": {
          const select = h("select", {
            class: "prb-select",
            onchange: (e) => {
              node.kind = e.target.value;
              render();
            },
          });
          [
            { v: "start", l: "^ start of string" },
            { v: "end", l: "$ end of string" },
            { v: "word", l: "\\b word boundary (GNU grep only)" },
            { v: "nonword", l: "\\B non-word-boundary (GNU grep only)" },
          ].forEach((o) => {
            const opt = h("option", { value: o.v, text: o.l });
            if (o.v === node.kind) opt.setAttribute("selected", "selected");
            select.appendChild(opt);
          });
          const warn =
            node.kind === "word" || node.kind === "nonword"
              ? h("p", { class: "prb-hint prb-hint-warn", text: "⚠ not POSIX ERE — works with GNU grep/Rust regex, but may fail on BSD grep (older macOS)." })
              : null;
          return cardShell(node, idx, count, ctx, "Anchor", [select, warn]);
        }

        case "group": {
          const altsWrap = h("div", { class: "prb-alternatives" });
          node.alternatives.forEach((alt, altIdx) => {
            const altCtx = {
              remove: (i) => {
                alt.nodes.splice(i, 1);
                render();
              },
              move: (i, dir) => {
                const j = i + dir;
                if (j < 0 || j >= alt.nodes.length) return;
                const [n] = alt.nodes.splice(i, 1);
                alt.nodes.splice(j, 0, n);
                render();
              },
            };
            const lane = h("div", { class: "prb-alt-lane" }, [
              renderSequence(alt, altCtx),
              h("div", { class: "prb-alt-controls" }, [
                h("div", { class: "prb-alt-add" }, [
                  ...["literal", "charclass", "wildcard", "group", "raw"].map((type) =>
                    h("button", {
                      class: "prb-btn prb-btn-add prb-btn-xs",
                      type: "button",
                      text: "+ " + labelForType(type),
                      onclick: () => {
                        alt.nodes.push(defaultNode(type));
                        render();
                      },
                    })
                  ),
                ]),
                node.alternatives.length > 1
                  ? h("button", {
                      class: "prb-btn prb-btn-ghost prb-btn-xs",
                      type: "button",
                      text: "remove this alternative",
                      onclick: () => {
                        node.alternatives.splice(altIdx, 1);
                        render();
                      },
                    })
                  : null,
              ]),
            ]);
            altsWrap.appendChild(lane);
            if (altIdx < node.alternatives.length - 1) {
              altsWrap.appendChild(h("div", { class: "prb-or-divider", text: "OR" }));
            }
          });
          return cardShell(node, idx, count, ctx, "Group ( … | … )", [
            altsWrap,
            h("button", {
              class: "prb-btn prb-btn-add prb-btn-xs",
              type: "button",
              text: "+ add alternative",
              onclick: () => {
                node.alternatives.push(makeSequence([defaultNode("literal")]));
                render();
              },
            }),
          ]);
        }

        case "raw":
          return cardShell(node, idx, count, ctx, "Raw regex", [
            h("input", {
              class: "prb-input prb-mono",
              type: "text",
              value: node.text,
              placeholder: "any regex fragment, inserted verbatim",
              oninput: (e) => {
                node.text = e.target.value;
                renderOutputOnly();
              },
              onchange: render,
            }),
            h("p", { class: "prb-hint prb-hint-warn", text: "⚠ not escaped or validated — you're responsible for valid syntax here." }),
          ]);

        default:
          return h("div", {});
      }
    }

    function currentPattern() {
      return (state.anchorStart ? "^" : "") + renderSequenceRegex(state.root) + (state.anchorEnd ? "$" : "");
    }

    let outputEl = null;

    function buildOutput() {
      const pattern = currentPattern();
      let compiled = null;
      let error = null;
      try {
        compiled = new RegExp(pattern);
      } catch (e) {
        error = e.message;
      }

      const patternCode = h("code", { class: "prb-pattern", text: pattern || "(empty)" });

      const testInput = h("textarea", {
        class: "prb-input prb-textarea",
        rows: "3",
        placeholder: "Paste a sample commit subject / branch / tag name to test it live…",
        oninput: (e) => {
          testValue = e.target.value;
          updateTestResult();
        },
      });
      testInput.value = testValue;

      const testResult = h("div", { class: "prb-test-result" });

      function updateTestResult() {
        testResult.innerHTML = "";
        if (error) {
          testResult.appendChild(h("span", { class: "prb-badge prb-badge-bad", text: "invalid regex: " + error }));
          return;
        }
        const lines = testValue.split("\n").filter((l) => l.length > 0);
        if (lines.length === 0) {
          testResult.appendChild(h("span", { class: "prb-hint", text: "Nothing to test yet." }));
          return;
        }
        lines.forEach((line) => {
          const ok = compiled.test(line);
          testResult.appendChild(
            h("div", { class: "prb-test-line" }, [
              h("span", { class: "prb-badge " + (ok ? "prb-badge-ok" : "prb-badge-bad"), text: ok ? "match" : "no match" }),
              h("code", { text: line }),
            ])
          );
        });
      }

      const sectionSelect = h("select", {
        class: "prb-select prb-select-sm",
        onchange: (e) => {
          state.section = e.target.value;
          renderOutputOnly();
        },
      });
      ["commit", "branch", "tag"].forEach((s) => {
        const opt = h("option", { value: s, text: "[" + s + "]" });
        if (s === state.section) opt.setAttribute("selected", "selected");
        sectionSelect.appendChild(opt);
      });

      const quoteWarning = pattern.includes("'")
        ? h("p", {
            class: "prb-hint prb-hint-warn",
            text: "⚠ this pattern contains a ' character — TOML literal strings can't contain one at all, so you'll need a double-quoted string with backslashes doubled instead of the snippet below.",
          })
        : null;

      const tomlLines = ["[" + state.section + "]", "pattern = '" + pattern + "'"].join("\n");
      const tomlCode = h("pre", { class: "prb-toml" }, [h("code", { text: tomlLines })]);

      const copyPatternBtn = h("button", {
        class: "prb-btn",
        type: "button",
        text: "Copy pattern",
        onclick: (e) => copyToClipboard(pattern, e.target),
      });
      const copyTomlBtn = h("button", {
        class: "prb-btn",
        type: "button",
        text: "Copy as TOML snippet",
        onclick: (e) => copyToClipboard(tomlLines, e.target),
      });

      const out = h("div", { class: "prb-output" }, [
        h("h4", { text: "Generated pattern" }),
        h("div", { class: "prb-pattern-row" }, [patternCode, error ? h("span", { class: "prb-badge prb-badge-bad", text: "invalid: " + error }) : null]),
        quoteWarning,
        h("label", { class: "prb-field-label", text: "target section in config.toml" }),
        sectionSelect,
        h("div", { class: "prb-output-actions" }, [copyPatternBtn, copyTomlBtn]),
        h("pre", { class: "prb-hint-pre" }, [tomlCode]),
        h("h4", { text: "Try it" }),
        testInput,
        testResult,
      ]);

      updateTestResult();
      outputEl = out;
      return out;
    }

    // Lightweight path for text/number inputs: re-render only the output
    // panel on every keystroke (cheap) instead of the whole tree, which
    // would steal focus out of the input being typed into.
    function renderOutputOnly() {
      const next = buildOutput();
      outputEl.replaceWith(next);
      outputEl = next;
    }

    function copyToClipboard(text, btn) {
      const done = () => {
        const old = btn.textContent;
        btn.textContent = "Copied!";
        setTimeout(() => (btn.textContent = old), 1200);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, done);
      } else {
        const ta = document.createElement("textarea");
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        try {
          document.execCommand("copy");
        } catch (e) {
          /* ignore */
        }
        document.body.removeChild(ta);
        done();
      }
    }

    render();
  }

  function init() {
    const root = document.getElementById("patou-regex-builder");
    if (root) App(root);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
