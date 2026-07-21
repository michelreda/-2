// ---------------------------------------------------------------------------
// Session State — persists and restores all dialog form state across sessions.
//
// Strategy
//   Serialises everything into prefs.form (same localStorage key as prefs).
//   Restoration happens AFTER cabinet-init.js re-applies type defaults on
//   setUnits(), so saved values always win over the defaults.
//
// Depends on (must already be loaded):
//   constants.js       – MATERIAL_PRESETS, DOOR_PRESETS, HANDLE_PRESETS, …
//   selector-wiring.js – applySelectorPreset(), toggleGrain()
//   cabinet-init.js    – wraps window.setUnits (we wrap it again, outermost)
//   new_cabinet.js     – loadPrefs(), savePrefs(), createGroupElement(),
//                        createItemElement(), onGroupTypeChange(),
//                        onItemTypeChange(), selectDoorPreset(),
//                        selectHandlePreset(), selectDrawerPreset(),
//                        selectDrawerHandlePreset(), selectPanelFacePreset(),
//                        selectedDoor/Handle/Drawer/DrawerHandle/PanelFacePresetId,
//                        updateBackPanelFields(), updateTotalHeight(),
//                        updateToeKickFields(), updateLegsFields()
//
// Load order: LAST – placed after cabinet-init.js in the HTML.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

// Fields whose values are expressed in the active unit system.
// When the saved unit differs from the current one these are skipped during
// restore so that the per-type defaults (already applied by cabinet-init.js)
// are kept and the dialog shows correct values for the new unit.
var UNIT_SENSITIVE_FIELD_IDS = new Set([
  "cabinet-width",
  "cabinet-height",
  "cabinet-depth",
  "cabinet-height-from-floor",
  "toe-kick-height",
  "toe-kick-depth",
  "panel-thickness",
  "back-panel-thickness",
  "back-panel-recess",
  "back-groove-depth",
  "back-groove-clearance",
  "stretcher-width",
  "overlay-clearance",
  "door-handle-offset-h",
  "door-handle-offset-v",
  "drawer-handle-offset-h",
  "drawer-handle-offset-v",
]);

var FORM_FIELD_IDS = [
  // General
  "cabinet-id",
  "cabinet-name",
  "cabinet-price",
  "cabinet-width",
  "cabinet-height",
  "cabinet-depth",
  "cabinet-height-from-floor",
  // Toe kick
  "toe-kick-enabled",
  "toe-kick-height",
  "toe-kick-depth",
  "skirting-enabled",
  "create-legs",
  "flat-sides",
  "flat-back",
  // Construction — carcass
  "top-panel",
  "base-panel",
  "side-panels",
  "panel-thickness",
  // Construction — corner
  "corner-type",
  "blind-accessible-side",
  // Construction — back panel
  "back-panel-type",
  "back-panel-thickness",
  "back-panel-recess",
  "back-panel-joinery",
  "back-groove-depth",
  "back-groove-clearance",
  "stretcher-count",
  "stretcher-width",
  // Construction — overlay
  "overlay-type",
  "overlay-clearance",
  // Global handle offsets (door / drawer tabs)
  "door-handle-offset-h",
  "door-handle-offset-v",
  "door-handle-rotation",
  "drawer-handle-offset-h",
  "drawer-handle-offset-v",
  "drawer-handle-rotation",
  // Item params panel (shared panel; reflects last-edited item)
  "item-handle-offset",
  "item-handle-vertical-offset",
  "hinges-count",
  "hinge-top-offset",
  "hinge-bottom-offset",
  "drawer-box",
  "drawer-top-clearance",
  "drawer-bottom-clearance",
  "opening-amount",
  // NOTE: item-height and item-shelves-count are intentionally excluded —
  // they are always repopulated from the item's dataset on selection.
];

// Each entry describes a selector button and which preset array backs it.
var SELECTOR_SAVE_DEFS = [
  {
    key: "material-carcass",
    swatchId: "material-carcass-swatch",
    labelId: "material-carcass-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "material-panel",
    swatchId: "material-panel-swatch",
    labelId: "material-panel-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "material-edge",
    swatchId: "material-edge-swatch",
    labelId: "material-edge-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "material-door",
    swatchId: "material-door-swatch",
    labelId: "material-door-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "material-drawer",
    swatchId: "material-drawer-swatch",
    labelId: "material-drawer-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "material-handle",
    swatchId: "material-handle-swatch",
    labelId: "material-handle-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "material-glass",
    swatchId: "material-glass-swatch",
    labelId: "material-glass-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "legs-panel",
    swatchId: "legs-panel-swatch",
    labelId: "legs-panel-label",
    hasGrain: false,
    arr: function () {
      return LEG_PRESETS;
    },
  },
  {
    key: "item-material",
    swatchId: "item-material-swatch",
    labelId: "item-material-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
  {
    key: "item-shape",
    swatchId: "item-shape-swatch",
    labelId: "item-shape-label",
    hasGrain: false,
    arr: function () {
      return DOOR_PRESETS.concat(DRAWER_PRESETS).concat(
        typeof PANEL_FACE_PRESETS !== "undefined" ? PANEL_FACE_PRESETS : [],
      );
    },
  },
  {
    key: "item-handle",
    swatchId: "item-handle-swatch",
    labelId: "item-handle-label",
    hasGrain: false,
    arr: function () {
      return HANDLE_PRESETS.concat(DRAWER_HANDLE_PRESETS);
    },
  },
  {
    key: "item-appliance",
    swatchId: "item-appliance-swatch",
    labelId: "item-appliance-label",
    hasGrain: false,
    arr: function () {
      return typeof APPLIANCE_PRESETS !== "undefined" ? APPLIANCE_PRESETS : [];
    },
  },
  {
    key: "item-profile",
    swatchId: "item-profile-swatch",
    labelId: "item-profile-label",
    hasGrain: false,
    arr: function () {
      return typeof PROFILE_PRESETS !== "undefined" ? PROFILE_PRESETS : [];
    },
  },
  {
    key: "item-profile-material",
    swatchId: "item-profile-material-swatch",
    labelId: "item-profile-material-label",
    hasGrain: true,
    arr: function () {
      return MATERIAL_PRESETS;
    },
  },
];

// ---------------------------------------------------------------------------
// Guards
// ---------------------------------------------------------------------------

// Set to true after setUnits() completes — enables auto-save.
var _sessionInitDone = false;

// Debounce handle for save throttling.
var _saveTimer = null;

function _debouncedSave() {
  if (!_sessionInitDone || _editMode) return;
  clearTimeout(_saveTimer);
  _saveTimer = setTimeout(saveFormState, 300);
}

// ---------------------------------------------------------------------------
// Collect helpers
// ---------------------------------------------------------------------------

function _collectFields() {
  var fields = {};
  FORM_FIELD_IDS.forEach(function (id) {
    var el = document.getElementById(id);
    if (!el) return;
    fields[id] = el.type === "checkbox" ? el.checked : el.value;
  });
  return fields;
}

// Dataset keys persisted per-item (presets, offsets, hinges, drawer, etc.)
var ITEM_DATASET_KEYS = [
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

function _collectConfigGroups() {
  var groups = [];
  var container = document.getElementById("configuration-items-container");
  if (!container) return groups;
  container
    .querySelectorAll(":scope > .group:not(.hidden-divider)")
    .forEach(function (groupEl) {
      var typeSel = groupEl.querySelector(".group-type");
      var header = groupEl.querySelector(".group-header");
      var group = {
        type: typeSel ? typeSel.value : "",
        height_cm: header ? header.dataset.heightCm || "0" : "0",
        height_in: header ? header.dataset.heightIn || "0" : "0",
        collapsed: groupEl.classList.contains("collapsed"),
        items: [],
      };
      // Persist profile shape + material for profile-group headers
      if (group.type === "profile-group" && header) {
        if (header.dataset.profileId)
          group.profileId = header.dataset.profileId;
        if (header.dataset.profileMaterialId)
          group.profileMaterialId = header.dataset.profileMaterialId;
        group.profileMaterialGrain =
          header.dataset.profileMaterialGrain || "horizontal";
      }
      groupEl
        .querySelectorAll(":scope > .item:not(.hidden-divider)")
        .forEach(function (itemEl) {
          var itemSel = itemEl.querySelector(".item-type");
          var saved = { type: itemSel ? itemSel.value : "" };
          ITEM_DATASET_KEYS.forEach(function (k) {
            if (itemEl.dataset[k] !== undefined) saved[k] = itemEl.dataset[k];
          });
          group.items.push(saved);
        });
      groups.push(group);
    });
  return groups;
}

function _collectSelectors() {
  var result = {};
  SELECTOR_SAVE_DEFS.forEach(function (def) {
    var labelEl = document.getElementById(def.labelId);
    if (!labelEl) return;
    var state = { presetId: labelEl.dataset.presetId || null };
    if (def.hasGrain) {
      var selectorBtn = document.getElementById(def.key + "-selector");
      var grainBtn =
        selectorBtn && selectorBtn.closest(".input-group")
          ? selectorBtn.closest(".input-group").querySelector(".grain-btn")
          : null;
      state.grain = grainBtn ? grainBtn.dataset.grain : "horizontal";
    }
    result[def.key] = state;
  });
  return result;
}

// ---------------------------------------------------------------------------
// saveFormState — public; called by auto-save machinery
// ---------------------------------------------------------------------------

function saveFormState() {
  var doorsEl = document.getElementById("door-leaves-panel");
  var drawersEl = document.getElementById("drawer-fronts-panel");
  var groups = _collectConfigGroups();
  savePrefs({
    form: {
      unit: typeof currentUnit !== "undefined" ? currentUnit : "cm",
      fields: _collectFields(),
      groups: groups,
      presets: {
        door: selectedDoorPresetId,
        doorHandle: selectedHandlePresetId,
        drawer: selectedDrawerPresetId,
        drawerHandle: selectedDrawerHandlePresetId,
        panel: selectedPanelFacePresetId,
      },
      selectors: _collectSelectors(),
      subTabs: {
        doors:
          doorsEl && !doorsEl.classList.contains("hidden")
            ? "leaves"
            : "handles",
        drawers:
          drawersEl && !drawersEl.classList.contains("hidden")
            ? "fronts"
            : "handles",
      },
    },
  });
}

// ---------------------------------------------------------------------------
// Restore helpers
// ---------------------------------------------------------------------------

function _restoreConfigList(groups) {
  var container = document.getElementById("configuration-items-container");
  if (!container) return;
  container.innerHTML = "";
  // Suppress per-group/item recompute calls; we do one final pass at the end
  if (typeof _suppressHiddenDividers !== "undefined")
    _suppressHiddenDividers = true;
  groups.forEach(function (groupDef) {
    var groupEl = createGroupElement();
    var groupSel = groupEl.querySelector(".group-type");
    var groupHeader = groupEl.querySelector(".group-header");
    if (groupSel && groupDef.type) {
      groupSel.value = groupDef.type;
      onGroupTypeChange(groupSel);
    }
    if (groupHeader) {
      groupHeader.dataset.heightCm = groupDef.height_cm || "0";
      groupHeader.dataset.heightIn = groupDef.height_in || "0";
      // Restore profile data for profile-group headers
      if (groupDef.type === "profile-group") {
        if (groupDef.profileId)
          groupHeader.dataset.profileId = groupDef.profileId;
        if (groupDef.profileMaterialId)
          groupHeader.dataset.profileMaterialId = groupDef.profileMaterialId;
        if (groupDef.profileMaterialGrain)
          groupHeader.dataset.profileMaterialGrain =
            groupDef.profileMaterialGrain;
      }
    }
    if (groupDef.collapsed) {
      groupEl.classList.add("collapsed");
      var collapseBtn = groupEl.querySelector(".btn-collapse");
      if (collapseBtn) collapseBtn.title = "Expand group";
    }
    (groupDef.items || []).forEach(function (itemDef) {
      var itemEl = createItemElement();
      var itemSel = itemEl.querySelector(".item-type");
      if (itemSel && itemDef.type) {
        itemSel.value = itemDef.type;
        onItemTypeChange(itemSel);
      }
      // Restore all saved dataset attributes (overrides defaults from onItemTypeChange)
      ITEM_DATASET_KEYS.forEach(function (k) {
        if (itemDef[k] !== undefined) itemEl.dataset[k] = itemDef[k];
      });
      groupEl.appendChild(itemEl);
    });
    container.appendChild(groupEl);
  });
  if (typeof _suppressHiddenDividers !== "undefined")
    _suppressHiddenDividers = false;

  // Enforce minimum divider height (panel thickness) after restore.
  // Separators have no enforced minimum — their saved value is preserved as-is.
  if (typeof _minDividerHeight === "function") {
    var minCm = _minDividerHeight("cm");
    var minIn = _minDividerHeight("in");
    container
      .querySelectorAll(".group:not(.hidden-divider)")
      .forEach(function (groupEl) {
        var gSel = groupEl.querySelector(".group-type");
        var gType = gSel ? gSel.value : "";
        if (gType === "divider-group") {
          var gh = groupEl.querySelector(".group-header");
          if (gh) {
            if (parseFloat(gh.dataset.heightCm) < minCm)
              gh.dataset.heightCm = minCm;
            if (parseFloat(gh.dataset.heightIn) < minIn)
              gh.dataset.heightIn = minIn;
          }
        }
        groupEl.querySelectorAll(":scope > .item").forEach(function (itemEl) {
          var iSel = itemEl.querySelector(".item-type");
          var iType = iSel ? iSel.value : "";
          if (iType === "divider") {
            if (parseFloat(itemEl.dataset.heightCm) < minCm)
              itemEl.dataset.heightCm = minCm;
            if (parseFloat(itemEl.dataset.heightIn) < minIn)
              itemEl.dataset.heightIn = minIn;
          }
        });
      });
  }

  // Insert auto dividers between items/groups that lack an explicit separator
  if (typeof recomputeHiddenDividers === "function") recomputeHiddenDividers();
}

function _restoreSelectors(selectors) {
  SELECTOR_SAVE_DEFS.forEach(function (def) {
    var state = selectors[def.key];
    if (!state || !state.presetId) return;
    var preset = def.arr().find(function (p) {
      return p.id === state.presetId;
    });
    if (!preset) return;
    applySelectorPreset(def.swatchId, def.labelId, preset);
    if (def.hasGrain && state.grain) {
      var selectorBtn = document.getElementById(def.key + "-selector");
      var grainBtn =
        selectorBtn && selectorBtn.closest(".input-group")
          ? selectorBtn.closest(".input-group").querySelector(".grain-btn")
          : null;
      if (grainBtn && grainBtn.dataset.grain !== state.grain) {
        toggleGrain(grainBtn);
      }
    }
  });
}

// ---------------------------------------------------------------------------
// restoreFormState — applies prefs.form to the live dialog
// ---------------------------------------------------------------------------

function restoreFormState() {
  var prefs = loadPrefs();
  var form = prefs.form;
  if (!form) return;

  // Detect whether the saved unit matches the live unit.  When they differ,
  // dimension fields are skipped so cabinet-init.js's per-type defaults
  // (already applied for the new unit) are preserved.
  var liveUnit = typeof currentUnit !== "undefined" ? currentUnit : "cm";
  var savedUnit = form.unit || "cm";
  var unitChanged = savedUnit !== liveUnit;

  // 1. Simple form fields
  var fields = form.fields || {};
  FORM_FIELD_IDS.forEach(function (id) {
    if (!(id in fields)) return;
    if (unitChanged && UNIT_SENSITIVE_FIELD_IDS.has(id)) return;
    var el = document.getElementById(id);
    if (!el) return;
    if (el.type === "checkbox") {
      el.checked = fields[id];
    } else {
      el.value = fields[id];
    }
  });

  // 2. Configuration list (groups + items with their exact dataset values)
  if (Array.isArray(form.groups)) {
    _restoreConfigList(form.groups);
  }

  // 3. Preset card selections (doors / handles / drawers / drawer-handles tab)
  var presets = form.presets || {};
  if (presets.door) selectDoorPreset(presets.door);
  if (presets.doorHandle) selectHandlePreset(presets.doorHandle);
  if (presets.drawer) selectDrawerPreset(presets.drawer);
  if (presets.drawerHandle) selectDrawerHandlePreset(presets.drawerHandle);
  if (presets.panel) selectPanelFacePreset(presets.panel);

  // 4. Material / shape / handle / appliance selectors
  if (form.selectors) _restoreSelectors(form.selectors);

  // 5. Sub-tab states
  var subTabs = form.subTabs || {};
  if (subTabs.doors) switchDoorsPanel(subTabs.doors);
  if (subTabs.drawers) switchDrawersPanel(subTabs.drawers);

  // 6. Re-sync all derived/conditional UI states now that field values changed
  updateBackPanelFields();
  updateTotalHeight();
  if (typeof updateCornerFields === "function") updateCornerFields();
  var toeKickEl = document.getElementById("toe-kick-enabled");
  if (toeKickEl) updateToeKickFields(toeKickEl);
  var legsEl = document.getElementById("create-legs");
  if (legsEl) updateLegsFields(legsEl);
  var drawerBoxEl = document.getElementById("drawer-box");
  if (drawerBoxEl && typeof updateDrawerBoxFields === "function")
    updateDrawerBoxFields(drawerBoxEl);
}

// ---------------------------------------------------------------------------
// Auto-save wiring — runs once on DOMContentLoaded
// ---------------------------------------------------------------------------

function initSessionState() {
  // Debounced save on all native form field changes
  document.addEventListener("input", _debouncedSave);
  document.addEventListener("change", _debouncedSave);

  // MutationObserver covers selector preset changes (data-preset-id,
  // data-grain), config structure changes (childList), group collapsed state
  // and preset card selections (class attribute).
  var body = document.body;
  if (body) {
    new MutationObserver(_debouncedSave).observe(body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: [
        "data-preset-id",
        "data-grain",
        "data-height-cm",
        "data-height-in",
        "data-shelves-count",
        "data-material-id",
        "data-material-grain",
        "data-shape-id",
        "data-handle-id",
        "data-handle-offset-h",
        "data-handle-offset-v",
        "data-hinges-count",
        "data-hinge-top-offset",
        "data-hinge-bottom-offset",
        "data-drawer-box",
        "data-drawer-top-clearance",
        "data-drawer-bottom-clearance",
        "data-opening-amount",
        "data-appliance-id",
        "data-profile-id",
        "data-profile-material-id",
        "data-profile-material-grain",
        "class",
      ],
    });
  }
}

// ---------------------------------------------------------------------------
// Wrap window.setUnits — restore saved state AFTER cabinet-init.js re-applies
// defaults (cabinet-init.js's own wrapper is already in place at this point).
// This wrapper runs outermost and therefore last in the call chain.
// ---------------------------------------------------------------------------
(function () {
  var _origSetUnits = window.setUnits;
  window.setUnits = function (unit) {
    _origSetUnits.call(this, unit); // → cabinet-init.js wrapper → original
    if (!_editMode) {
      restoreFormState(); // overrides any defaults applied above
      // Sync the 3D preview with the fully-restored form state
      if (typeof _cabinetPreview !== "undefined" && _cabinetPreview) {
        _cabinetPreview.requestUpdate();
      }
    }
    _sessionInitDone = true; // enable auto-save from this point forward
  };
})();

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------
document.addEventListener("DOMContentLoaded", function () {
  initSessionState();
});
