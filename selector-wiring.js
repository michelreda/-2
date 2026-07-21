// ---------------------------------------------------------------------------
// Selector Wiring — connects every .selector button in this dialog to
// PresetModal, and updates the button's swatch + label on confirmation.
//
// Depends on: constants.js (preset arrays), preset-modal.js (PresetModal)
// Called from: new_cabinet.js DOMContentLoaded → initSelectorButtons()
// ---------------------------------------------------------------------------

// Door-like item types whose shape selector should show DOOR_PRESETS
const DOOR_ITEM_TYPES = new Set([
  "door-hinge-right",
  "door-hinge-left",
  "door-hinge-top",
  "door-hinge-bottom",
  "double-door",
]);

// Drawer-like item types whose shape selector should show DRAWER_PRESETS
const DRAWER_ITEM_TYPES = new Set(["drawer", "false-drawer"]);

// Panel item types whose shape selector should show PANEL_FACE_PRESETS
const PANEL_ITEM_TYPES = new Set(["panel"]);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Apply a confirmed preset to a selector button.
 * Updates the swatch background (if preset.color is set) and the label text.
 */
function applySelectorPreset(swatchId, labelId, preset) {
  const label = document.getElementById(labelId);
  const swatch = document.getElementById(swatchId);
  if (label) {
    label.textContent = preset.label;
    label.classList.remove("selector-label--default");
    label.dataset.presetId = preset.id;
  }
  if (swatch) {
    // Store raw values so the 3D preview can read them without parsing CSS
    swatch.dataset.textureUrl = preset.thumbnail || "";
    swatch.dataset.color = preset.color || "";
    swatch.dataset.source = preset.source || "";
    if (preset.thumbnail) {
      swatch.style.background = `url('${preset.thumbnail}') center/contain no-repeat`;
    } else if (preset.color) {
      swatch.style.background = preset.color;
    }
  }
}

function _getActiveConfigElement() {
  return document.querySelector(
    "#configuration-items-container .item.selected, " +
      "#configuration-items-container .group-header.selected",
  );
}

function _setClearBtnState(btnId, enabled) {
  const btn = document.getElementById(btnId);
  if (!btn) return;
  btn.disabled = !enabled;
}

function _applyClearBtnIcon(btnId) {
  const btn = document.getElementById(btnId);
  if (!btn || typeof ICON_RELOAD === "undefined") return;
  btn.innerHTML = ICON_RELOAD;
}

function _syncItemOverrideClearButtons(el) {
  _setClearBtnState(
    "item-material-clear-btn",
    !!(el && el.dataset && el.dataset.materialId),
  );
  _setClearBtnState(
    "item-shape-clear-btn",
    !!(el && el.dataset && el.dataset.shapeId),
  );
  _setClearBtnState(
    "item-handle-clear-btn",
    !!(el && el.dataset && el.dataset.handleId),
  );
  _setClearBtnState(
    "item-profile-material-clear-btn",
    !!(el && el.dataset && el.dataset.profileMaterialId),
  );
}

function _clearItemOverride(datasetKey, grainDatasetKey) {
  const active = _getActiveConfigElement();
  if (!active) return;
  delete active.dataset[datasetKey];
  if (grainDatasetKey) delete active.dataset[grainDatasetKey];
  if (typeof _restoreItemSelectors === "function") {
    _restoreItemSelectors(active);
  }
}

/**
 * Apply grain direction to a grain toggle button.
 * Updates data-grain, icon SVG, and tooltip title.
 */
function _applyGrainToBtn(grainBtn, grain) {
  if (!grainBtn || !grain || !GRAIN_ICONS[grain]) return;
  grainBtn.dataset.grain = grain;
  grainBtn.innerHTML = GRAIN_ICONS[grain];
  grainBtn.title =
    grain === "horizontal"
      ? "Grain direction: Horizontal \u2014 click to switch to Vertical"
      : "Grain direction: Vertical \u2014 click to switch to Horizontal";
}

/**
 * Wire a single selector button to open the modal with the given config.
 * `presetsGetter` is a function so it can resolve dynamic arrays at open-time.
 * `grainDatasetKey` (optional) — dataset key to persist grain on the active
 *   item element (e.g. "materialGrain", "profileMaterialGrain").
 */
function _wireSelector(
  btnId,
  title,
  presetsGetter,
  swatchId,
  labelId,
  datasetKey,
  presetType,
  grainDatasetKey,
) {
  const btn = document.getElementById(btnId);
  if (!btn) return;
  btn.addEventListener("click", function () {
    PresetModal.open({
      title: title,
      presets: presetsGetter(),
      selected: null,
      presetType: presetType || null,
      onConfirm: function (preset) {
        applySelectorPreset(swatchId, labelId, preset);

        // If the material preset has a saved grain direction, update the
        // adjacent grain toggle button immediately.
        if (preset.grain) {
          const inputGroup = btn.closest(".input-group");
          const grainBtnEl =
            inputGroup && inputGroup.querySelector(".grain-btn");
          _applyGrainToBtn(grainBtnEl, preset.grain);
        }

        if (datasetKey || grainDatasetKey) {
          const active = _getActiveConfigElement();
          if (active) {
            if (datasetKey) active.dataset[datasetKey] = preset.id;
            if (grainDatasetKey && preset.grain)
              active.dataset[grainDatasetKey] = preset.grain;
            _syncItemOverrideClearButtons(active);
          }
        }
      },
    });
  });
}

// ---------------------------------------------------------------------------
// Shape preset resolution — picks door or drawer presets by item context
// ---------------------------------------------------------------------------

/**
 * Returns the appropriate shape presets for the currently "active" item.
 * Falls back to combining both lists if no item context is known.
 */
function _getShapePresets() {
  // Primary: use the currently selected item in the configuration panel
  const selectedType = document.querySelector(
    "#configuration-items-container .item.selected .item-type",
  );
  if (selectedType) {
    if (DOOR_ITEM_TYPES.has(selectedType.value)) return DOOR_PRESETS;
    if (DRAWER_ITEM_TYPES.has(selectedType.value)) return DRAWER_PRESETS;
    if (PANEL_ITEM_TYPES.has(selectedType.value)) return PANEL_FACE_PRESETS;
  }
  // Fallback: last-changed item-type select
  const lastChanged = document.querySelector(
    "#configuration-items-container .item-type[data-active]",
  );
  const value = lastChanged ? lastChanged.value : null;
  if (value && DOOR_ITEM_TYPES.has(value)) return DOOR_PRESETS;
  if (value && DRAWER_ITEM_TYPES.has(value)) return DRAWER_PRESETS;
  if (value && PANEL_ITEM_TYPES.has(value)) return PANEL_FACE_PRESETS;
  return [...DOOR_PRESETS, ...DRAWER_PRESETS];
}

function _getHandlePresets() {
  // Similar logic to _getShapePresets, but for handle vs drawer handle presets
  const selectedType = document.querySelector(
    "#configuration-items-container .item.selected .item-type",
  );
  if (selectedType) {
    if (DOOR_ITEM_TYPES.has(selectedType.value)) return HANDLE_PRESETS;
    if (DRAWER_ITEM_TYPES.has(selectedType.value)) return DRAWER_HANDLE_PRESETS;
  }
  // Fallback: last-changed item-type select
  const lastChanged = document.querySelector(
    "#configuration-items-container .item-type[data-active]",
  );
  const value = lastChanged ? lastChanged.value : null;
  if (value && DOOR_ITEM_TYPES.has(value)) return HANDLE_PRESETS;
  if (value && DRAWER_ITEM_TYPES.has(value)) return DRAWER_HANDLE_PRESETS;
  return [...HANDLE_PRESETS, ...DRAWER_HANDLE_PRESETS];
}

// ---------------------------------------------------------------------------
// Main init — called once from DOMContentLoaded in new_cabinet.js
// ---------------------------------------------------------------------------

function initSelectorButtons() {
  _applyClearBtnIcon("item-material-clear-btn");
  _applyClearBtnIcon("item-shape-clear-btn");
  _applyClearBtnIcon("item-handle-clear-btn");
  _applyClearBtnIcon("item-profile-material-clear-btn");

  // -- Configuration tab: item parameters ----------------------------------

  _wireSelector(
    "item-material-selector",
    "Select Material",
    () => MATERIAL_PRESETS,
    "item-material-swatch",
    "item-material-label",
    "materialId",
    "material",
    "materialGrain",
  );

  _wireSelector(
    "item-shape-selector",
    "Select Shape",
    _getShapePresets,
    "item-shape-swatch",
    "item-shape-label",
    "shapeId",
    "panel",
  );

  _wireSelector(
    "item-handle-selector",
    "Select Handle",
    _getHandlePresets,
    "item-handle-swatch",
    "item-handle-label",
    "handleId",
    "handle",
  );

  _wireSelector(
    "item-appliance-selector",
    "Select Appliance",
    () => APPLIANCE_PRESETS,
    "item-appliance-swatch",
    "item-appliance-label",
    "applianceId",
    "appliance",
  );

  // -- Profile material selector ------------------------------------------
  _wireSelector(
    "item-profile-material-selector",
    "Select Profile Material",
    () => MATERIAL_PRESETS,
    "item-profile-material-swatch",
    "item-profile-material-label",
    "profileMaterialId",
    "material",
    "profileMaterialGrain",
  );

  // -- Profile selector: custom wiring to auto-set height from profile width --
  (function () {
    const btn = document.getElementById("item-profile-selector");
    if (!btn) return;
    btn.addEventListener("click", function () {
      PresetModal.open({
        title: "Select Profile",
        presets: PROFILE_PRESETS,
        selected: null,
        presetType: "profile",
        onConfirm: function (preset) {
          applySelectorPreset(
            "item-profile-swatch",
            "item-profile-label",
            preset,
          );
          const active = document.querySelector(
            "#configuration-items-container .item.selected, " +
              "#configuration-items-container .group-header.selected",
          );
          if (active) {
            active.dataset.profileId = preset.id;
            // Auto-set height to the longest dimension of the profile (max of
            // width and height) so it works correctly in both horizontal and
            // vertical groups regardless of how the profile was drawn.
            const unit =
              typeof currentUnit !== "undefined" ? currentUnit : "cm";
            const curH =
              unit === "in"
                ? parseFloat(active.dataset.heightIn) || 0
                : parseFloat(active.dataset.heightCm) || 0;
            if (curH === 0) {
              const profileDim =
                unit === "in"
                  ? Math.max(preset.width_in || 0, preset.height_in || 0)
                  : Math.max(preset.width_cm || 0, preset.height_cm || 0);
              if (profileDim > 0) {
                if (unit === "in") {
                  active.dataset.heightIn = profileDim;
                } else {
                  active.dataset.heightCm = profileDim;
                }
                const heightEl = document.getElementById("item-height");
                if (heightEl) heightEl.value = profileDim;
              }
            }
          }
        },
      });
    });
  })();

  // -- Item-level clear override buttons ---------------------------------
  const clearMaterialBtn = document.getElementById("item-material-clear-btn");
  if (clearMaterialBtn) {
    clearMaterialBtn.addEventListener("click", function (e) {
      e.preventDefault();
      _clearItemOverride("materialId", "materialGrain");
    });
  }

  const clearShapeBtn = document.getElementById("item-shape-clear-btn");
  if (clearShapeBtn) {
    clearShapeBtn.addEventListener("click", function (e) {
      e.preventDefault();
      _clearItemOverride("shapeId");
    });
  }

  const clearHandleBtn = document.getElementById("item-handle-clear-btn");
  if (clearHandleBtn) {
    clearHandleBtn.addEventListener("click", function (e) {
      e.preventDefault();
      _clearItemOverride("handleId");
    });
  }

  const clearProfileMaterialBtn = document.getElementById(
    "item-profile-material-clear-btn",
  );
  if (clearProfileMaterialBtn) {
    clearProfileMaterialBtn.addEventListener("click", function (e) {
      e.preventDefault();
      _clearItemOverride("profileMaterialId", "profileMaterialGrain");
    });
  }

  _syncItemOverrideClearButtons(null);

  // -- Materials tab -------------------------------------------------------

  _wireSelector(
    "material-carcass-selector",
    "Select Carcass Material",
    () => MATERIAL_PRESETS,
    "material-carcass-swatch",
    "material-carcass-label",
    undefined,
    "material",
  );

  _wireSelector(
    "material-panel-selector",
    "Select Panel Material",
    () => MATERIAL_PRESETS,
    "material-panel-swatch",
    "material-panel-label",
    undefined,
    "material",
  );

  _wireSelector(
    "material-edge-selector",
    "Select Edge Material",
    () => MATERIAL_PRESETS,
    "material-edge-swatch",
    "material-edge-label",
    undefined,
    "material",
  );

  _wireSelector(
    "material-door-selector",
    "Select Door Material",
    () => MATERIAL_PRESETS,
    "material-door-swatch",
    "material-door-label",
    undefined,
    "material",
  );

  _wireSelector(
    "material-drawer-selector",
    "Select Drawer Material",
    () => MATERIAL_PRESETS,
    "material-drawer-swatch",
    "material-drawer-label",
    undefined,
    "material",
  );

  _wireSelector(
    "material-handle-selector",
    "Select Handle Material",
    () => MATERIAL_PRESETS,
    "material-handle-swatch",
    "material-handle-label",
    undefined,
    "material",
  );

  _wireSelector(
    "material-glass-selector",
    "Select Glass Material",
    () => MATERIAL_PRESETS,
    "material-glass-swatch",
    "material-glass-label",
    undefined,
    "material",
  );

  // -- Toe Kick tab: leg shape --------------------------------------------

  _wireSelector(
    "legs-panel-selector",
    "Select Leg Shape",
    () => LEG_PRESETS,
    "legs-panel-swatch",
    "legs-panel-label",
    undefined,
    "leg",
  );

  // -- Track active item type for shape context ----------------------------
  // Mark the last-changed item-type select with data-active so _getShapePresets
  // can read the right value.
  document
    .getElementById("configuration-items-container")
    .addEventListener("change", function (e) {
      if (!e.target.classList.contains("item-type")) return;
      // Remove marker from all, apply to the changed one
      document
        .querySelectorAll("#configuration-items-container .item-type")
        .forEach((s) => s.removeAttribute("data-active"));
      e.target.setAttribute("data-active", "1");
    });
}

// Ruby → JS  (allows Ruby to push material presets at runtime)
window.initMaterialPresets = function (params) {
  const data = typeof params === "string" ? JSON.parse(params) : params;
  MATERIAL_PRESETS.length = 0;
  (data.presets || []).forEach((p) => MATERIAL_PRESETS.push(p));
};

window.initAppliancePresets = function (params) {
  const data = typeof params === "string" ? JSON.parse(params) : params;
  APPLIANCE_PRESETS.length = 0;
  (data.presets || []).forEach((p) => APPLIANCE_PRESETS.push(p));
};

window.initProfilePresets = function (params) {
  const data = typeof params === "string" ? JSON.parse(params) : params;
  const arr = Array.isArray(data) ? data : data.presets || [];
  arr.forEach((p) => {
    if (!PROFILE_PRESETS.some((existing) => existing.id === p.id)) {
      PROFILE_PRESETS.push(p);
    }
  });
};

// ---------------------------------------------------------------------------
// Item selector restore — called from config-selection.js → _applyItemExtended
// ---------------------------------------------------------------------------

/**
 * Reset a selector button to its default (no-preset) state, or apply a stored preset.
 */
function _restoreSelectorBtn(
  btnId,
  swatchId,
  labelId,
  defaultLabel,
  presetId,
  presets,
) {
  const label = document.getElementById(labelId);
  const swatch = document.getElementById(swatchId);
  if (!label) return;
  if (!presetId) {
    label.textContent = defaultLabel;
    label.classList.add("selector-label--default");
    delete label.dataset.presetId;
    if (swatch) swatch.style.background = "";
    return;
  }
  const preset = presets.find(function (p) {
    return p.id === presetId;
  });
  if (preset) applySelectorPreset(swatchId, labelId, preset);
}

/**
 * Restore all four item-level selector buttons from an item element's dataset.
 * Called by config-selection.js → _applyItemExtended.
 */
function _restoreItemSelectors(el) {
  _restoreSelectorBtn(
    "item-material-selector",
    "item-material-swatch",
    "item-material-label",
    "Use Cabinet Material",
    el.dataset.materialId,
    MATERIAL_PRESETS,
  );
  _restoreSelectorBtn(
    "item-shape-selector",
    "item-shape-swatch",
    "item-shape-label",
    "Use Cabinet Shape",
    el.dataset.shapeId,
    _getShapePresets(),
  );
  _restoreSelectorBtn(
    "item-handle-selector",
    "item-handle-swatch",
    "item-handle-label",
    "Use Cabinet Handle",
    el.dataset.handleId,
    _getHandlePresets(),
  );
  _restoreSelectorBtn(
    "item-appliance-selector",
    "item-appliance-swatch",
    "item-appliance-label",
    "Select Appliance",
    el.dataset.applianceId,
    APPLIANCE_PRESETS,
  );
  _restoreSelectorBtn(
    "item-profile-selector",
    "item-profile-swatch",
    "item-profile-label",
    "Select Profile",
    el.dataset.profileId,
    PROFILE_PRESETS,
  );
  _restoreSelectorBtn(
    "item-profile-material-selector",
    "item-profile-material-swatch",
    "item-profile-material-label",
    "Use Handle Material",
    el.dataset.profileMaterialId,
    MATERIAL_PRESETS,
  );
  // Restore profile material grain button
  const profGrainBtn = document.querySelector(
    '.param-group[data-param="profile"] .grain-btn',
  );
  if (profGrainBtn && typeof GRAIN_ICONS !== "undefined") {
    const grain = el.dataset.profileMaterialGrain || "vertical";
    profGrainBtn.dataset.grain = grain;
    profGrainBtn.innerHTML = GRAIN_ICONS[grain];
    profGrainBtn.title =
      grain === "horizontal"
        ? "Grain direction: Horizontal — click to switch to Vertical"
        : "Grain direction: Vertical — click to switch to Horizontal";
  }

  _syncItemOverrideClearButtons(el);
}
