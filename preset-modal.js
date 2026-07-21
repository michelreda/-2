// ---------------------------------------------------------------------------
// PresetModal — reusable preset picker. Lives in shared/ so any dialog can
// include it. Provides two usage modes:
//
//   MODAL (overlay) — for picking a value inside another dialog:
//     PresetModal.open({ title, presets, selected, onConfirm, presetType })
//     PresetModal.close()
//
//   EMBED (inline) — renders the grid directly into a container element,
//   controlled by the host dialog's own toolbar/filters:
//     PresetModal.embed(containerEl, { presets, presetType, onSelect, onDelete,
//                                      emptyStateEl, onRender })
//     PresetModal.embedFilter(kind, value)
//       kind: 'type'   → filter by p.cabinet_type  (value: 'all' | type string)
//             'source' → filter by user/builtin     (value: 'all' | 'user' | 'builtin')
//             'search' → text search on label+dims  (value: string)
//
// presetType values: "material" | "handle" | "door" | "drawer" | "leg" |
//                    "appliance" | "cabinet" | <any string>
//
// Multiple embed instances are supported — each call to PresetModal.embed()
// returns a numeric embedId that callers must pass to embedSetPresets() and
// embedFilter().  Inline card onclick attrs receive the same id.
//
// The consumer dialog must register the `sketchup.delete_preset` callback in
// Ruby if deletion of user presets is desired. If the callback is absent, the
// delete button is still shown but the bridge call is silently skipped.
// ---------------------------------------------------------------------------

const PresetModal = (function () {
  let _el = null; // overlay element (created once, for modal mode)
  let _confirmDlg = null; // <dialog> for delete confirmation (shared by both modes)
  let _state = {}; // modal mode state

  // Multi-instance embed map: embedId (number) → state object
  var _embedInstances = {};
  var _nextEmbedId = 0;

  // -- Build delete-confirm dialog (shared, created lazily) ----------------
  function _ensureDeleteDialog() {
    if (_confirmDlg) return;
    const dlg = document.createElement("dialog");
    dlg.id = "preset-modal-delete-confirm";
    dlg.className = "confirm-dialog";
    dlg.innerHTML =
      `<h4 class="confirm-dialog__title">Delete Preset?</h4>` +
      `<p class="confirm-dialog__body" id="preset-modal-delete-confirm-body"></p>` +
      `<div class="confirm-dialog__footer">` +
      `<button class="btn btn-ghost" id="preset-modal-delete-cancel-btn">Cancel</button>` +
      `<button class="btn btn-danger" id="preset-modal-delete-confirm-btn">Delete</button>` +
      `</div>`;
    document.body.appendChild(dlg);
    _confirmDlg = dlg;
  }

  // -- Build modal overlay DOM (once) --------------------------------------
  function _build() {
    const el = document.createElement("div");
    el.id = "preset-modal-overlay";
    el.className = "preset-modal-overlay hidden";
    el.innerHTML =
      `<div class="preset-modal" role="dialog" aria-modal="true" aria-labelledby="preset-modal-title">` +
      `<div class="preset-modal__header">` +
      `<span class="preset-modal__title" id="preset-modal-title"></span>` +
      `<button class="btn btn-icon preset-modal__close" onclick="PresetModal.close()" title="Close">` +
      `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"` +
      ` fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">` +
      `<path d="M18 6 6 18"/><path d="m6 6 12 12"/>` +
      `</svg>` +
      `</button>` +
      `</div>` +
      `<div class="preset-modal__filters filter-pills"></div>` +
      `<div class="preset-modal__body">` +
      `<div class="preset-grid" id="preset-modal-grid"></div>` +
      `</div>` +
      `<div class="preset-modal__footer">` +
      `<button class="btn btn-ghost" onclick="PresetModal.close()">Cancel</button>` +
      `<button class="btn btn-primary" onclick="PresetModal._confirm()">Select</button>` +
      `</div>` +
      `</div>`;
    document.body.appendChild(el);

    // Close on backdrop click
    el.addEventListener("click", function (e) {
      if (e.target === el) PresetModal.close();
    });

    _ensureDeleteDialog();
    return el;
  }

  // Ordered display names for known source categories
  var _CATEGORY_ORDER = [
    "wood",
    "marble",
    "metal",
    "color",
    "glass",
    "builtin",
  ];
  var _CATEGORY_LABELS = {
    wood: "Wood",
    marble: "Marble",
    metal: "Metal",
    color: "Color",
    glass: "Glass",
    builtin: "Built-in",
    user: "User Created",
  };

  var _MATERIAL_CATEGORY_SET = new Set([
    "wood",
    "marble",
    "metal",
    "color",
    "glass",
  ]);

  function _normalizeMaterialPreset(p) {
    var source = (p.source || "").toLowerCase();
    var category = (p.category || "").toLowerCase();
    var sourceFilter = p.user_created ? "user" : "builtin";

    // Built-in seed presets use `source` as category (wood/marble/…)
    // while library presets provide an explicit `category` field.
    if (
      !_MATERIAL_CATEGORY_SET.has(category) &&
      _MATERIAL_CATEGORY_SET.has(source)
    ) {
      category = source;
    }

    return {
      ...p,
      _sourceFilter: sourceFilter,
      _categoryFilter: category,
    };
  }

  function _normalizeEmbedPresets(presetType, presets) {
    var list = presets || [];
    return presetType === "material"
      ? list.map(_normalizeMaterialPreset)
      : list;
  }

  // -- Filter pills --------------------------------------------------------
  function _renderFilters() {
    const pills = _el.querySelector(".preset-modal__filters");

    if (_state.presetType === "material") {
      const hasUser = _state.presets.some(function (p) {
        return p._sourceFilter === "user";
      });
      const categories = new Set(
        _state.presets
          .map(function (p) {
            return p._categoryFilter;
          })
          .filter(Boolean),
      );
      const orderedCats = _CATEGORY_ORDER.filter(function (c) {
        return categories.has(c);
      });

      let sourceHtml =
        `<span class="text-muted fw-600">Library:</span>` +
        `<button class="filter-pill${_state.sourceFilter === "all" ? " active" : ""}" data-filter-kind="source" data-filter="all" onclick="PresetModal._setFilter(this)">All</button>` +
        `<button class="filter-pill${_state.sourceFilter === "builtin" ? " active" : ""}" data-filter-kind="source" data-filter="builtin" onclick="PresetModal._setFilter(this)">Built-in</button>`;

      if (hasUser) {
        sourceHtml += `<button class="filter-pill${_state.sourceFilter === "user" ? " active" : ""}" data-filter-kind="source" data-filter="user" onclick="PresetModal._setFilter(this)">User Created</button>`;
      }

      let categoryHtml =
        `<span class="text-muted fw-600">Category:</span>` +
        `<button class="filter-pill${_state.categoryFilter === "all" ? " active" : ""}" data-filter-kind="category" data-filter="all" onclick="PresetModal._setFilter(this)">All</button>`;

      orderedCats.forEach(function (cat) {
        categoryHtml += `<button class="filter-pill${_state.categoryFilter === cat ? " active" : ""}" data-filter-kind="category" data-filter="${cat}" onclick="PresetModal._setFilter(this)">${_CATEGORY_LABELS[cat]}</button>`;
      });

      pills.innerHTML =
        `<div class="filter-pills">${sourceHtml}</div>` +
        `<div class="filter-pills">${categoryHtml}</div>`;
      return;
    }

    const sources = new Set(
      _state.presets.map(function (p) {
        return p.source;
      }),
    );
    const ordered = _CATEGORY_ORDER.filter(function (c) {
      return sources.has(c);
    });
    let html =
      '<div class="filter-pills">' +
      `<span class="text-muted fw-600">Library:</span>` +
      `<button class="filter-pill active" data-filter-kind="single" data-filter="all" onclick="PresetModal._setFilter(this)">All</button>`;
    ordered.forEach(function (cat) {
      html += `<button class="filter-pill" data-filter-kind="single" data-filter="${cat}" onclick="PresetModal._setFilter(this)">${_CATEGORY_LABELS[cat]}</button>`;
    });
    html +=
      `<button class="filter-pill" data-filter-kind="single" data-filter="user" onclick="PresetModal._setFilter(this)">User Created</button>` +
      "</div>";
    pills.innerHTML = html;
  }

  // -- Card grid -----------------------------------------------------------
  function _renderGrid() {
    const grid = _el.querySelector("#preset-modal-grid");
    const filtered = _state.presets
      .filter(function (p) {
        if (_state.presetType === "material") {
          const sourceOk =
            _state.sourceFilter === "all" ||
            p._sourceFilter === _state.sourceFilter;
          const categoryOk =
            _state.categoryFilter === "all" ||
            p._categoryFilter === _state.categoryFilter;
          return sourceOk && categoryOk;
        }
        return _state.filter === "all" || p.source === _state.filter;
      })
      .sort((a, b) => (a.label || "").localeCompare(b.label || ""));
    if (filtered.length === 0) {
      grid.innerHTML = `<p class="preset-modal__empty">No presets found.</p>`;
      return;
    }
    grid.innerHTML = filtered
      .map(
        (p) =>
          `<div class="preset-card${_state.selected === p.id ? " selected" : ""}"` +
          ` data-id="${p.id}" onclick="PresetModal._selectCard('${p.id}')">` +
          (p.source === "user"
            ? `<button class="preset-card__delete" onclick="event.stopPropagation(); PresetModal._deleteCard('${p.id}')" title="Delete preset">&times;</button>`
            : "") +
          `<div class="preset-card__thumb"` +
          (!p.thumbnail && p.color
            ? ` style="background-color:${p.color}"`
            : "") +
          `>` +
          (p.thumbnail
            ? `<img src="${p.thumbnail}" alt="${p.label}" loading="lazy">`
            : "") +
          `</div>` +
          `<div class="preset-card__label">${p.label}</div>` +
          `</div>`,
      )
      .join("");
  }

  function _clearSelection() {
    _state.selected = null;
    _el
      .querySelectorAll("#preset-modal-grid .preset-card")
      .forEach((card) => card.classList.remove("selected"));
  }

  // ── Embed private helpers ────────────────────────────────────────────────

  var _CABINET_TYPE_LABELS = {
    base: "Base",
    wall: "Wall",
    tall: "Tall",
    "base-corner": "Base Corner",
    "wall-corner": "Wall Corner",
    high: "High Cabinet",
    filler: "Filler",
  };

  function _renderEmbedGrid(instanceId) {
    var es = _embedInstances[instanceId];
    if (!es || !es.containerEl) return;

    var filtered = es.allPresets
      .filter(function (p) {
        if (es.presetType === "material") {
          var sourceOk =
            es.sourceFilter === "all" || p._sourceFilter === es.sourceFilter;
          var categoryOk =
            es.categoryFilter === "all" ||
            p._categoryFilter === es.categoryFilter;
          if (!sourceOk || !categoryOk) return false;
        } else {
          var isUser = p.source === "user" || p.user_created;
          if (es.sourceFilter === "builtin" && isUser) return false;
          if (es.sourceFilter === "user" && !isUser) return false;
          if (
            es.typeFilter &&
            es.typeFilter !== "all" &&
            p.cabinet_type !== es.typeFilter
          )
            return false;
        }
        if (es.searchText) {
          var hay = (
            (p.label || "") +
            " " +
            (p.dimensions || "") +
            " " +
            (p.description || "") +
            " " +
            (p.category || p._categoryFilter || "")
          ).toLowerCase();
          if (hay.indexOf(es.searchText) === -1) return false;
        }
        return true;
      })
      .sort(function (a, b) {
        return (a.label || "").localeCompare(b.label || "");
      });

    var count = filtered.length;

    if (es.emptyStateEl) {
      es.emptyStateEl.style.display = count === 0 ? "" : "none";
    }
    es.containerEl.style.display = count === 0 ? "none" : "";

    if (count === 0) {
      es.containerEl.innerHTML = "";
      if (typeof es.onRender === "function") es.onRender(0);
      return;
    }

    var iid = instanceId;
    es.containerEl.innerHTML = filtered
      .map(function (p) {
        var isUser =
          es.presetType === "material"
            ? p._sourceFilter === "user"
            : p.source === "user" || p.user_created;
        var deleteHtml = isUser
          ? `<button class="preset-card__delete" onclick="event.stopPropagation(); PresetModal._deleteEmbedCard('${p.id}',${iid})" title="Delete preset">&times;</button>`
          : "";

        var thumbHtml = p.thumbnail
          ? `<div class="preset-card__thumb"><img src="${p.thumbnail}" alt="${p.label}" loading="lazy"></div>`
          : `<div class="preset-card__thumb${
              es.presetType === "material" && p.color
                ? ""
                : " preset-card__thumb--placeholder"
            }"${
              es.presetType === "material" && p.color
                ? ` style="background:${p.color}"`
                : ""
            }>` +
            (es.presetType === "material" && p.color
              ? ""
              : `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">` +
                `<rect x="2" y="7" width="20" height="14" rx="2"/>` +
                `<path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/>` +
                `</svg>`) +
            `</div>`;

        var badge = isUser
          ? `<span class="badge badge-user">User</span>`
          : `<span class="badge badge-builtin">Built-in</span>`;
        var typeLabel = p.cabinet_type
          ? `<span class="preset-type-label">${_CABINET_TYPE_LABELS[p.cabinet_type] || p.cabinet_type}</span>`
          : "";
        var materialLabel =
          es.presetType === "material" && p._categoryFilter
            ? `<span class="preset-type-label">${_CATEGORY_LABELS[p._categoryFilter] || p._categoryFilter}</span>`
            : "";
        var dimsHtml = p.dimensions
          ? `<span class="preset-card__dims">${p.dimensions}</span>`
          : "";
        var infoHtml =
          p.dimensions || p.cabinet_type || es.presetType === "material"
            ? `<div class="preset-card__info">` +
              `<span class="preset-card__name">${p.label}</span>` +
              dimsHtml +
              `<div class="preset-card__meta">${
                es.presetType === "material" ? materialLabel : typeLabel
              }${badge}</div>` +
              `</div>`
            : `<div class="preset-card__label">${p.label}</div>`;

        return (
          `<div class="preset-card${es.selectedId === p.id ? " selected" : ""}" data-id="${p.id}" onclick="PresetModal._selectEmbedCard('${p.id}',${iid})">` +
          deleteHtml +
          thumbHtml +
          infoHtml +
          `</div>`
        );
      })
      .join("");

    if (typeof es.onRender === "function") es.onRender(count);
  }

  // -- Public API ----------------------------------------------------------
  return {
    open: function ({ title, presets, selected, onConfirm, presetType }) {
      if (!_el) _el = _build();
      const modalBody = _el.querySelector(".preset-modal__body");
      if (modalBody && !modalBody.dataset.emptyClickBound) {
        modalBody.addEventListener("click", function (e) {
          if (!e.target.closest(".preset-card")) _clearSelection();
        });
        modalBody.dataset.emptyClickBound = "1";
      }
      _state = {
        presets:
          presetType === "material"
            ? (presets || []).map(_normalizeMaterialPreset)
            : presets || [],
        selected: selected || null,
        onConfirm: onConfirm,
        filter: "all",
        sourceFilter: "all",
        categoryFilter: "all",
        presetType: presetType || null,
      };
      _el.querySelector("#preset-modal-title").textContent =
        title || "Select Preset";
      _renderFilters();
      _renderGrid();
      _el.classList.remove("hidden");
      _el.querySelector(".preset-modal__close").focus();
    },

    close: function () {
      if (_el) _el.classList.add("hidden");
    },

    _setFilter: function (btn) {
      const group = btn.parentElement;
      group
        .querySelectorAll(".filter-pill")
        .forEach((p) => p.classList.remove("active"));
      btn.classList.add("active");

      const kind = btn.dataset.filterKind || "single";
      if (kind === "source") {
        _state.sourceFilter = btn.dataset.filter;
      } else if (kind === "category") {
        _state.categoryFilter = btn.dataset.filter;
      } else {
        _state.filter = btn.dataset.filter;
      }

      _renderGrid();
    },

    _selectCard: function (id) {
      _state.selected = id;
      _el
        .querySelectorAll("#preset-modal-grid .preset-card")
        .forEach((card) =>
          card.classList.toggle("selected", card.dataset.id === id),
        );
    },

    _confirm: function () {
      if (!_state.selected) return;
      const preset = _state.presets.find((p) => p.id === _state.selected);
      if (preset && typeof _state.onConfirm === "function") {
        _state.onConfirm(preset);
      }
      this.close();
    },

    _deleteCard: function (id) {
      const preset = _state.presets.find((p) => p.id === id);
      if (!preset || preset.source !== "user") return;

      _ensureDeleteDialog();
      const body = _confirmDlg.querySelector(
        "#preset-modal-delete-confirm-body",
      );
      const confirmBtn = _confirmDlg.querySelector(
        "#preset-modal-delete-confirm-btn",
      );
      const cancelBtn = _confirmDlg.querySelector(
        "#preset-modal-delete-cancel-btn",
      );
      if (!confirmBtn || !cancelBtn) return;

      if (body)
        body.textContent = `"${preset.label}" will be permanently removed. This cannot be undone.`;

      // Replace buttons to avoid accumulating listeners
      const newConfirm = confirmBtn.cloneNode(true);
      const newCancel = cancelBtn.cloneNode(true);
      confirmBtn.parentNode.replaceChild(newConfirm, confirmBtn);
      cancelBtn.parentNode.replaceChild(newCancel, cancelBtn);

      newCancel.addEventListener("click", function () {
        _confirmDlg.close();
      });
      newConfirm.addEventListener("click", function () {
        _confirmDlg.close();
        // Ask Ruby to delete from disk — sketchup.delete_preset must be
        // registered by the host dialog's Ruby counterpart.
        if (typeof sketchup !== "undefined" && sketchup.delete_preset) {
          sketchup.delete_preset(
            JSON.stringify({
              type: _state.presetType || "unknown",
              id: id,
              name: preset.label.replace(/ /g, "_"),
            }),
          );
        }
        // Remove from the local array
        const idx = _state.presets.indexOf(preset);
        if (idx !== -1) _state.presets.splice(idx, 1);
        if (_state.selected === id) _state.selected = null;
        _renderGrid();
        // Optional toast — call host-defined helper if available
        if (typeof _showDefaultsToast === "function")
          _showDefaultsToast(`Preset "${preset.label}" deleted`);
      });

      _confirmDlg.showModal();
    },

    // ── Embed API ──────────────────────────────────────────────────────────
    //
    // Renders the preset grid inline into `containerEl`.
    // The host dialog controls filtering via embedFilter(kind, value).
    //
    // Options:
    //   presets      — initial array of preset objects
    //   presetType   — passed through to delete bridge (e.g. "cabinet")
    //   onSelect(p)  — called when a card is clicked
    //   onDelete(p)  — called after a user preset is deleted from Ruby
    //   emptyStateEl — optional element to show/hide when grid is empty
    //   onRender(n)  — optional callback with the visible count after each render
    // -----------------------------------------------------------------------
    // ── Embed API ──────────────────────────────────────────────────────────
    // embed(containerEl, opts) → returns embedId (number)
    // embedSetPresets(embedId, presets)
    // embedFilter(embedId, kind, value)
    // -----------------------------------------------------------------------
    embed: function (containerEl, opts) {
      if (!containerEl) return null;
      _ensureDeleteDialog();
      opts = opts || {};
      var instanceId = ++_nextEmbedId;
      _embedInstances[instanceId] = {
        containerEl: containerEl,
        allPresets: _normalizeEmbedPresets(
          opts.presetType || null,
          opts.presets,
        ),
        presetType: opts.presetType || null,
        onSelect: opts.onSelect || null,
        onDelete: opts.onDelete || null,
        emptyStateEl: opts.emptyStateEl || null,
        onRender: opts.onRender || null,
        selectedId: null,
        typeFilter: "all",
        sourceFilter: "all",
        categoryFilter: "all",
        searchText: "",
      };
      _renderEmbedGrid(instanceId);
      return instanceId;
    },

    // Update embed filters and re-render.
    // kind: 'type' | 'source' | 'search'
    embedFilter: function (embedId, kind, value) {
      var es = _embedInstances[embedId];
      if (!es) return;
      if (kind === "type") es.typeFilter = value || "all";
      if (kind === "source") es.sourceFilter = value || "all";
      if (kind === "category") es.categoryFilter = value || "all";
      if (kind === "search") es.searchText = (value || "").toLowerCase().trim();
      _renderEmbedGrid(embedId);
    },

    // Replace the preset list then re-render (called after Ruby sends data).
    embedSetPresets: function (embedId, presets) {
      var es = _embedInstances[embedId];
      if (!es) return;
      es.allPresets = _normalizeEmbedPresets(es.presetType, presets);
      _renderEmbedGrid(embedId);
    },

    embedClearSelection: function (embedId) {
      var es = _embedInstances[embedId];
      if (!es || !es.selectedId) return false;
      es.selectedId = null;
      es.containerEl
        .querySelectorAll(".preset-card.selected")
        .forEach(function (card) {
          card.classList.remove("selected");
        });
      return true;
    },

    // Called from inline onclick on embed cards.
    _selectEmbedCard: function (presetId, embedId) {
      var es = _embedInstances[embedId];
      if (!es) return;
      var preset = es.allPresets.find(function (p) {
        return p.id === presetId;
      });
      if (!preset) return;
      // Update selected state and reflect in DOM
      es.selectedId = presetId;
      es.containerEl.querySelectorAll(".preset-card").forEach(function (card) {
        card.classList.toggle("selected", card.dataset.id === presetId);
      });
      if (typeof es.onSelect === "function") es.onSelect(preset);
    },

    // Called from inline onclick on embed delete buttons.
    _deleteEmbedCard: function (presetId, embedId) {
      var es = _embedInstances[embedId];
      if (!es) return;
      var preset = es.allPresets.find(function (p) {
        return p.id === presetId;
      });
      if (!preset) return;
      var isUser = preset.source === "user" || preset.user_created;
      if (!isUser) return;

      _ensureDeleteDialog();
      var body = _confirmDlg.querySelector("#preset-modal-delete-confirm-body");
      var confirmBtn = _confirmDlg.querySelector(
        "#preset-modal-delete-confirm-btn",
      );
      var cancelBtn = _confirmDlg.querySelector(
        "#preset-modal-delete-cancel-btn",
      );
      if (!confirmBtn || !cancelBtn) return;

      if (body)
        body.textContent = `"${preset.label}" will be permanently removed. This cannot be undone.`;

      var newConfirm = confirmBtn.cloneNode(true);
      var newCancel = cancelBtn.cloneNode(true);
      confirmBtn.parentNode.replaceChild(newConfirm, confirmBtn);
      cancelBtn.parentNode.replaceChild(newCancel, cancelBtn);

      newCancel.addEventListener("click", function () {
        _confirmDlg.close();
      });
      newConfirm.addEventListener("click", function () {
        _confirmDlg.close();
        if (typeof sketchup !== "undefined" && sketchup.delete_preset) {
          sketchup.delete_preset(
            JSON.stringify({
              type: es.presetType || "unknown",
              id: presetId,
              name: preset.label.replace(/ /g, "_"),
            }),
          );
        }
        if (typeof es.onDelete === "function") es.onDelete(preset);
        var idx = es.allPresets.indexOf(preset);
        if (idx !== -1) es.allPresets.splice(idx, 1);
        _renderEmbedGrid(embedId);
      });

      _confirmDlg.showModal();
    },
  };
})();

// Close overlay on Escape key (embed mode is always visible — no close needed)
document.addEventListener("keydown", function (e) {
  if (e.key === "Escape") PresetModal.close();
});
