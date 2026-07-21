// ---------------------------------------------------------------------------
// Cabinet Init — applies CABINET_DEFAULTS for the selected cabinet type to
// every section of the dialog: dimensions, toe kick, construction, config
// list, door/drawer preset selections, and material selectors.
//
// Depends on:
//   cabinet-defaults.js  → CABINET_DEFAULTS
//   constants.js         → MATERIAL_PRESETS, DOOR_PRESETS, etc.
//   selector-wiring.js   → applySelectorPreset()
//   new_cabinet.js       → createGroupElement(), createItemElement(),
//                          onGroupTypeChange(), selectDoorPreset(),
//                          selectHandlePreset(), selectDrawerPreset(),
//                          selectDrawerHandlePreset(), updateBackPanelFields()
//
// Called from: new_cabinet.js DOMContentLoaded → initCabinetDefaults()
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Low-level field helpers
// ---------------------------------------------------------------------------

function _setValue(id, val) {
  var el = document.getElementById(id);
  if (el) el.value = val;
}

function _setChecked(id, val) {
  var el = document.getElementById(id);
  if (el) el.checked = val;
}

function _setSelect(id, val) {
  var el = document.getElementById(id);
  if (el) el.value = val;
}

function _setValueStep(id, value, unit) {
  var el = document.getElementById(id);
  if (!el) return;
  el.value = value;
  var steps = DIMENSION_STEPS[unit];
  if (steps && steps[id] !== undefined) el.step = steps[id];
}

// ---------------------------------------------------------------------------
// Section appliers
// ---------------------------------------------------------------------------

function _applyDimensions(def, unit) {
  var dims = def.dimensions[unit] || def.dimensions.cm;
  var toeKickH = def.toeKick.enabled
    ? unit === "in"
      ? def.toeKick.height_in
      : def.toeKick.height_cm
    : 0;
  _setValueStep("cabinet-width", dims.width, unit);
  _setValueStep("cabinet-height", dims.height, unit);
  _setValueStep("cabinet-depth", dims.depth, unit);
  _setValueStep("cabinet-height-from-floor", dims.heightFromFloor, unit);
  _setValueStep(
    "cabinet-total-height",
    dims.height + dims.heightFromFloor,
    unit,
  );
}

function _applyToeKick(def, unit) {
  var tk = def.toeKick;
  _setChecked("toe-kick-enabled", tk.enabled);
  _setValueStep(
    "toe-kick-height",
    unit === "in" ? tk.height_in : tk.height_cm,
    unit,
  );
  _setValueStep(
    "toe-kick-depth",
    unit === "in" ? tk.depth_in : tk.depth_cm,
    unit,
  );
  _setChecked("skirting-enabled", tk.skirting);
  _setChecked("create-legs", tk.createLegs);
  _setChecked("flat-sides", tk.flatSides);
  _setChecked("flat-back", tk.flatBack);
  // Sync disabled states to match the new checkbox values
  var toeKickEl = document.getElementById("toe-kick-enabled");
  if (toeKickEl && typeof updateToeKickFields === "function")
    updateToeKickFields(toeKickEl);
  var legsEl = document.getElementById("create-legs");
  if (legsEl && typeof updateLegsFields === "function")
    updateLegsFields(legsEl);
}

function _applyConstruction(def, unit) {
  var c = def.construction;
  _setSelect("top-panel", c.topPanel);
  _setSelect("base-panel", c.basePanel);
  _setSelect("side-panels", c.sidePanels);
  _setValueStep(
    "panel-thickness",
    unit === "in" ? c.panelThickness_in : c.panelThickness_cm,
    unit,
  );
  _setSelect("back-panel-type", c.backPanelType);
  _setValueStep(
    "back-panel-thickness",
    unit === "in" ? c.backPanelThickness_in : c.backPanelThickness_cm,
    unit,
  );
  _setValueStep(
    "back-panel-recess",
    unit === "in" ? c.backPanelRecess_in : c.backPanelRecess_cm,
    unit,
  );
  _setSelect("back-panel-joinery", c.backPanelJoinery || "grooved");
  _setValueStep(
    "back-groove-depth",
    unit === "in"
      ? c.backGrooveDepth_in || 0.25
      : c.backGrooveDepth_cm || 0.6,
    unit,
  );
  _setValueStep(
    "back-groove-clearance",
    unit === "in"
      ? c.backGrooveClearance_in == null
        ? 0.03125
        : c.backGrooveClearance_in
      : c.backGrooveClearance_cm == null
        ? 0.1
        : c.backGrooveClearance_cm,
    unit,
  );
  _setValue("stretcher-count", c.stretcherCount);
  _setValueStep(
    "stretcher-width",
    unit === "in" ? c.stretcherWidth_in : c.stretcherWidth_cm,
    unit,
  );
  _setSelect("overlay-type", c.overlayType);
  _setValueStep(
    "overlay-clearance",
    unit === "in" ? c.overlayClearance_in : c.overlayClearance_cm,
    unit,
  );
  // Refresh dependent field visibility
  if (typeof updateBackPanelFields === "function") updateBackPanelFields();
}

function _applyConfigList(configDef) {
  var container = document.getElementById("configuration-items-container");
  if (!container) return;
  container.innerHTML = "";
  // Suppress per-group recompute calls; we do one final pass at the end
  if (typeof _suppressHiddenDividers !== "undefined")
    _suppressHiddenDividers = true;
  configDef.forEach(function (groupDef) {
    var groupEl = createGroupElement();
    var groupSel = groupEl.querySelector(".group-type");
    var groupHeader = groupEl.querySelector(".group-header");
    if (groupSel && groupDef.type) {
      groupSel.value = groupDef.type;
      onGroupTypeChange(groupSel);
    }
    if (groupHeader) {
      if (groupDef.height_cm !== undefined)
        groupHeader.dataset.heightCm = groupDef.height_cm;
      if (groupDef.height_in !== undefined)
        groupHeader.dataset.heightIn = groupDef.height_in;
    }
    (groupDef.items || []).forEach(function (itemDef) {
      var itemEl = createItemElement();
      var itemSel = itemEl.querySelector(".item-type");
      if (itemSel && itemDef.type) {
        itemSel.value = itemDef.type;
        if (typeof onItemTypeChange === "function") onItemTypeChange(itemSel);
      }
      // Restore all saved dataset attributes (overrides defaults from onItemTypeChange)
      var keys =
        typeof ITEM_DATASET_KEYS !== "undefined"
          ? ITEM_DATASET_KEYS
          : [
              "heightCm",
              "heightIn",
              "shelvesCount",
              "materialId",
              "materialGrain",
              "shapeId",
              "handleId",
              "handleOffsetH",
              "handleOffsetV",
              "hingesCount",
              "hingeTopOffset",
              "hingeBottomOffset",
              "drawerBox",
              "drawerTopClearance",
              "drawerBottomClearance",
              "openingAmount",
              "applianceId",
              "profileId",
              "profileMaterialId",
              "profileMaterialGrain",
            ];
      keys.forEach(function (k) {
        if (itemDef[k] !== undefined) itemEl.dataset[k] = itemDef[k];
      });
      // Support legacy keys from older saved defaults
      if (
        itemEl.dataset.heightCm === undefined &&
        itemDef.height_cm !== undefined
      )
        itemEl.dataset.heightCm = itemDef.height_cm;
      if (
        itemEl.dataset.heightIn === undefined &&
        itemDef.height_in !== undefined
      )
        itemEl.dataset.heightIn = itemDef.height_in;
      if (
        itemEl.dataset.shelvesCount === undefined &&
        itemDef.shelves !== undefined
      )
        itemEl.dataset.shelvesCount = itemDef.shelves;
      groupEl.appendChild(itemEl);
    });
    container.appendChild(groupEl);
  });
  if (typeof _suppressHiddenDividers !== "undefined")
    _suppressHiddenDividers = false;

  // Insert auto dividers between items/groups that lack an explicit separator
  if (typeof recomputeHiddenDividers === "function") recomputeHiddenDividers();
}

function _applyCorner(def) {
  if (def.cornerType) _setSelect("corner-type", def.cornerType);
  if (def.accessibleSide)
    _setSelect("blind-accessible-side", def.accessibleSide);
  if (typeof updateCornerFields === "function") updateCornerFields();
}

function _applyPresetSelections(def) {
  if (def.doors.shape) selectDoorPreset(def.doors.shape);
  if (def.doors.handle) selectHandlePreset(def.doors.handle);
  if (def.drawers.shape) selectDrawerPreset(def.drawers.shape);
  if (def.drawers.handle) selectDrawerHandlePreset(def.drawers.handle);
  if (def.panels && def.panels.shape) selectPanelFacePreset(def.panels.shape);
  if (def.toeKick && def.toeKick.legs) {
    var legPreset = LEG_PRESETS.find(function (p) {
      return p.id === def.toeKick.legs;
    });
    if (legPreset)
      applySelectorPreset("legs-panel-swatch", "legs-panel-label", legPreset);
  }
}

function _applyMaterials(def) {
  var map = [
    [
      "material-carcass-swatch",
      "material-carcass-label",
      def.materials.carcass,
    ],
    ["material-panel-swatch", "material-panel-label", def.materials.panel],
    ["material-edge-swatch", "material-edge-label", def.materials.edge],
    ["material-door-swatch", "material-door-label", def.materials.door],
    ["material-drawer-swatch", "material-drawer-label", def.materials.drawer],
    ["material-handle-swatch", "material-handle-label", def.materials.handle],
    ["material-glass-swatch", "material-glass-label", def.materials.glass],
  ];
  map.forEach(function (row) {
    var presetId = row[2];
    if (!presetId) return;
    var preset = MATERIAL_PRESETS.find(function (p) {
      return p.id === presetId;
    });
    if (preset) applySelectorPreset(row[0], row[1], preset);
  });
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// User-defaults helpers — localStorage key per cabinet type
// ---------------------------------------------------------------------------

var _USER_DEFAULTS_PREFIX = "mlc_user_defaults_";

/** Return the saved user defaults for `type`, or null if none. */
function _loadUserDefaults(type) {
  try {
    var raw = localStorage.getItem(_USER_DEFAULTS_PREFIX + type);
    return raw ? JSON.parse(raw) : null;
  } catch (_) {
    return null;
  }
}

/** Persist `def` as user defaults for `type`. */
function _saveUserDefaults(type, def) {
  try {
    localStorage.setItem(_USER_DEFAULTS_PREFIX + type, JSON.stringify(def));
  } catch (_) {}
}

/** Remove user defaults for `type`. */
function _clearUserDefaults(type) {
  try {
    localStorage.removeItem(_USER_DEFAULTS_PREFIX + type);
  } catch (_) {}
}

/**
 * Apply all defaults for the given cabinet type to the open dialog.
 * Safe to call at any time (on type change, on unit change, on init).
 * User-saved defaults (via makeDefaultForType) take precedence over CABINET_DEFAULTS.
 */
function applyCabinetDefaults(type) {
  var def = _loadUserDefaults(type) || CABINET_DEFAULTS[type];
  if (!def) return;
  var unit = typeof currentUnit !== "undefined" ? currentUnit : "cm";

  // Update the name placeholder (don't overwrite a value the user typed)
  var nameEl = document.getElementById("cabinet-name");
  if (nameEl && !nameEl.value) nameEl.placeholder = def.name;

  _applyDimensions(def, unit);
  _applyToeKick(def, unit);
  _applyConstruction(def, unit);
  _applyCorner(def);
  _applyConfigList(def.config);
  _applyPresetSelections(def);
  _applyMaterials(def);

  // Refresh 3D preview after defaults change
  if (typeof _cabinetPreview !== "undefined" && _cabinetPreview) {
    _cabinetPreview.requestUpdate();
  }
}

/**
 * Wire the cabinet-type select, then seed the initial state.
 * Called from new_cabinet.js DOMContentLoaded.
 */
function initCabinetDefaults() {
  var sel = document.getElementById("cabinet-id");
  if (!sel) return;

  sel.addEventListener("change", function () {
    // Clear the name field so the placeholder updates on type change
    var nameEl = document.getElementById("cabinet-name");
    if (nameEl) nameEl.value = "";
    applyCabinetDefaults(this.value);
  });

  if (sel.value) applyCabinetDefaults(sel.value);
}

// ---------------------------------------------------------------------------
// Intercept window.setUnits — re-apply per-type dimension defaults whenever
// the unit system changes (Ruby calls this after dialog_ready).
// ---------------------------------------------------------------------------
(function () {
  var _origSetUnits = window.setUnits;
  window.setUnits = function (unit) {
    // Let the original handler update currentUnit and unit labels
    _origSetUnits.call(this, unit);
    // Apply per-type dimension defaults (values + steps) for the active type
    var typeEl = document.getElementById("cabinet-id");
    if (typeEl && typeEl.value) {
      var def =
        _loadUserDefaults(typeEl.value) || CABINET_DEFAULTS[typeEl.value];
      if (def) {
        _applyDimensions(def, unit);
        _applyToeKick(def, unit);
        _applyConstruction(def, unit);
        // Re-apply presets and materials on first open (create mode only):
        // Ruby injects preset arrays before calling setUnits, so MATERIAL_PRESETS
        // etc. are populated by the time we get here — unlike at DOMContentLoaded.
        if (typeof _editMode === "undefined" || !_editMode) {
          _applyPresetSelections(def);
          _applyMaterials(def);
        }
      }
    }
    // Keep item-height step in sync for the currently displayed item
    var steps = DIMENSION_STEPS[unit];
    if (steps) {
      var itemHeightEl = document.getElementById("item-height");
      if (itemHeightEl) itemHeightEl.step = steps["item-height"];
    }
    // Refresh corner fields and total width for the new unit
    if (typeof updateCornerFields === "function") updateCornerFields();
    // Refresh 3D preview after unit change
    if (typeof _cabinetPreview !== "undefined" && _cabinetPreview) {
      _cabinetPreview.requestUpdate();
    }
  };
})();

// ---------------------------------------------------------------------------
// Collect current dialog state as a CABINET_DEFAULTS-shaped object
// ---------------------------------------------------------------------------

/** Walk the config DOM and return a simplified groups array. */
function _collectConfigForDefaults() {
  var container = document.getElementById("configuration-items-container");
  if (!container) return [];
  var groups = [];
  container.querySelectorAll(":scope > .group").forEach(function (groupEl) {
    if (groupEl.dataset.hiddenDivider === "true") return; // skip auto dividers
    var typeSel = groupEl.querySelector(".group-type");
    var gHeader = groupEl.querySelector(".group-header");
    var items = [];
    groupEl.querySelectorAll(":scope > .item").forEach(function (itemEl) {
      if (itemEl.dataset.hiddenDivider === "true") return;
      var itemSel = itemEl.querySelector(".item-type");
      var saved = { type: itemSel ? itemSel.value : "opening" };
      var keys =
        typeof ITEM_DATASET_KEYS !== "undefined"
          ? ITEM_DATASET_KEYS
          : [
              "heightCm",
              "heightIn",
              "shelvesCount",
              "materialId",
              "materialGrain",
              "shapeId",
              "handleId",
              "handleOffsetH",
              "handleOffsetV",
              "hingesCount",
              "hingeTopOffset",
              "hingeBottomOffset",
              "drawerBox",
              "drawerTopClearance",
              "drawerBottomClearance",
              "openingAmount",
              "applianceId",
              "profileId",
              "profileMaterialId",
              "profileMaterialGrain",
            ];
      keys.forEach(function (k) {
        if (itemEl.dataset[k] !== undefined) saved[k] = itemEl.dataset[k];
      });
      items.push(saved);
    });
    groups.push({
      type: typeSel ? typeSel.value : "vertical-group",
      height_cm: parseFloat(gHeader ? gHeader.dataset.heightCm : 0) || 0,
      height_in: parseFloat(gHeader ? gHeader.dataset.heightIn : 0) || 0,
      items: items,
    });
  });
  return groups;
}

/** Read all current dialog fields and produce a CABINET_DEFAULTS-shaped object. */
function _collectCurrentAsDefaults(type) {
  var unit = typeof currentUnit !== "undefined" ? currentUnit : "cm";
  var isCm = unit === "cm";

  function numEl(id) {
    var el = document.getElementById(id);
    return el ? parseFloat(el.value) || 0 : 0;
  }
  function strEl(id) {
    var el = document.getElementById(id);
    return el ? el.value : "";
  }
  function boolEl(id) {
    var el = document.getElementById(id);
    return el ? el.checked : false;
  }
  // Convert a value in the current unit to both cm and in
  function toCm(v) {
    return isCm ? v : v * 2.54;
  }
  function toIn(v) {
    return isCm ? v / 2.54 : v;
  }

  // Dimensions
  var w = numEl("cabinet-width");
  var h = numEl("cabinet-height");
  var d = numEl("cabinet-depth");
  var hff = numEl("cabinet-height-from-floor");

  // Toe kick
  var tkH = numEl("toe-kick-height");
  var tkD = numEl("toe-kick-depth");

  // Construction
  var pt = numEl("panel-thickness");
  var bpt = numEl("back-panel-thickness");
  var bpr = numEl("back-panel-recess");
  var bgd = numEl("back-groove-depth");
  var bgc = numEl("back-groove-clearance");
  var stW = numEl("stretcher-width");
  var ovCl = numEl("overlay-clearance");

  // Materials (uses _collectMaterial from new_cabinet.js — same global scope)
  function matOf(selectorId) {
    return typeof _collectMaterial === "function"
      ? _collectMaterial(selectorId).id
      : null;
  }

  // Preserve name and corner-specific fields from existing (factory) defaults
  var factoryDef = CABINET_DEFAULTS[type] || {};

  return {
    name: factoryDef.name || type,
    cornerType: strEl("corner-type") || factoryDef.cornerType || undefined,
    accessibleSide:
      strEl("blind-accessible-side") || factoryDef.accessibleSide || undefined,
    dimensions: {
      cm: {
        width: toCm(w),
        height: toCm(h),
        depth: toCm(d),
        heightFromFloor: toCm(hff),
      },
      in: {
        width: toIn(w),
        height: toIn(h),
        depth: toIn(d),
        heightFromFloor: toIn(hff),
      },
    },
    toeKick: {
      enabled: boolEl("toe-kick-enabled"),
      height_cm: toCm(tkH),
      height_in: toIn(tkH),
      depth_cm: toCm(tkD),
      depth_in: toIn(tkD),
      skirting: boolEl("skirting-enabled"),
      createLegs: boolEl("create-legs"),
      flatSides: boolEl("flat-sides"),
      flatBack: boolEl("flat-back"),
      legs:
        typeof _collectPreset === "function"
          ? _collectPreset("legs-panel-selector")
          : null,
    },
    construction: {
      topPanel: strEl("top-panel"),
      basePanel: strEl("base-panel"),
      sidePanels: strEl("side-panels"),
      panelThickness_cm: toCm(pt),
      panelThickness_in: toIn(pt),
      backPanelType: strEl("back-panel-type"),
      backPanelThickness_cm: toCm(bpt),
      backPanelThickness_in: toIn(bpt),
      backPanelRecess_cm: toCm(bpr),
      backPanelRecess_in: toIn(bpr),
      backPanelJoinery: strEl("back-panel-joinery") || "butt",
      backGrooveDepth_cm: toCm(bgd),
      backGrooveDepth_in: toIn(bgd),
      backGrooveClearance_cm: toCm(bgc),
      backGrooveClearance_in: toIn(bgc),
      stretcherCount: parseInt(strEl("stretcher-count")) || 2,
      stretcherWidth_cm: toCm(stW),
      stretcherWidth_in: toIn(stW),
      overlayType: strEl("overlay-type"),
      overlayClearance_cm: toCm(ovCl),
      overlayClearance_in: toIn(ovCl),
    },
    config: _collectConfigForDefaults(),
    doors: {
      shape:
        typeof selectedDoorPresetId !== "undefined"
          ? selectedDoorPresetId
          : null,
      handle:
        typeof selectedHandlePresetId !== "undefined"
          ? selectedHandlePresetId
          : null,
    },
    drawers: {
      shape:
        typeof selectedDrawerPresetId !== "undefined"
          ? selectedDrawerPresetId
          : null,
      handle:
        typeof selectedDrawerHandlePresetId !== "undefined"
          ? selectedDrawerHandlePresetId
          : null,
    },
    materials: {
      carcass: matOf("material-carcass-selector"),
      panel: matOf("material-panel-selector"),
      edge: matOf("material-edge-selector"),
      door: matOf("material-door-selector"),
      drawer: matOf("material-drawer-selector"),
      handle: matOf("material-handle-selector"),
      glass: matOf("material-glass-selector"),
    },
  };
}

// ---------------------------------------------------------------------------
// Toast helper
// ---------------------------------------------------------------------------

var _toastTimer = null;

function _showDefaultsToast(msg) {
  var toast = document.getElementById("defaults-toast");
  if (!toast) return;
  toast.textContent = msg;
  toast.classList.add("visible");
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(function () {
    toast.classList.remove("visible");
  }, 2200);
}

// ---------------------------------------------------------------------------
// Public: Make Default / Restore Factory Defaults
// ---------------------------------------------------------------------------

/**
 * Save the current dialog values as user defaults for the active cabinet type.
 * Shows a confirm dialog first; saves only on confirmation.
 */
function makeDefaultForType() {
  var typeEl = document.getElementById("cabinet-id");
  if (!typeEl || !typeEl.value) return;
  var type = typeEl.value;
  var label = (CABINET_DEFAULTS[type] && CABINET_DEFAULTS[type].name) || type;

  var dlg = document.getElementById("make-default-confirm");
  var bodyEl = document.getElementById("make-default-confirm-body");
  var confirmBtn = document.getElementById("make-default-confirm-btn");
  var cancelBtn = document.getElementById("make-default-cancel-btn");
  if (!dlg) return;

  if (bodyEl) {
    bodyEl.textContent =
      "The current settings will replace the defaults for \u201c" +
      label +
      "\u201d. " +
      "This only affects new cabinets of this type.";
  }

  // Wire up buttons — clone to clear any previous listeners
  var newConfirm = confirmBtn.cloneNode(true);
  var newCancel = cancelBtn.cloneNode(true);
  confirmBtn.parentNode.replaceChild(newConfirm, confirmBtn);
  cancelBtn.parentNode.replaceChild(newCancel, cancelBtn);

  newConfirm.addEventListener("click", function () {
    dlg.close();
    var saved = _collectCurrentAsDefaults(type);
    _saveUserDefaults(type, saved);
    _showDefaultsToast("Default saved for " + label);
  });

  newCancel.addEventListener("click", function () {
    dlg.close();
  });

  dlg.showModal();
}

/**
 * Clear any user-saved defaults for the active cabinet type and re-apply
 * the original factory defaults. Shows a confirm dialog first.
 */
function restoreFactoryDefaults() {
  var typeEl = document.getElementById("cabinet-id");
  if (!typeEl || !typeEl.value) return;
  var type = typeEl.value;
  var label = (CABINET_DEFAULTS[type] && CABINET_DEFAULTS[type].name) || type;

  var dlg = document.getElementById("restore-defaults-confirm");
  var bodyEl = document.getElementById("restore-defaults-confirm-body");
  var confirmBtn = document.getElementById("restore-defaults-confirm-btn");
  var cancelBtn = document.getElementById("restore-defaults-cancel-btn");
  if (!dlg) return;

  if (bodyEl) {
    var hasUserDefaults = !!_loadUserDefaults(type);
    bodyEl.textContent = hasUserDefaults
      ? "Your saved defaults for \u201c" +
        label +
        "\u201d will be discarded and the original factory settings restored."
      : "\u201c" + label + "\u201d is already using factory defaults.";
  }

  // Wire up buttons — clone to clear any previous listeners
  var newConfirm = confirmBtn.cloneNode(true);
  var newCancel = cancelBtn.cloneNode(true);
  confirmBtn.parentNode.replaceChild(newConfirm, confirmBtn);
  cancelBtn.parentNode.replaceChild(newCancel, cancelBtn);

  newConfirm.addEventListener("click", function () {
    dlg.close();
    var hadUserDefaults = !!_loadUserDefaults(type);
    _clearUserDefaults(type);
    applyCabinetDefaults(type);
    if (hadUserDefaults) {
      _showDefaultsToast("Factory defaults restored");
    }
  });

  newCancel.addEventListener("click", function () {
    dlg.close();
  });

  dlg.showModal();
}
