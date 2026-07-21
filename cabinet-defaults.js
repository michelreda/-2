// ---------------------------------------------------------------------------
// Cabinet Defaults — initial field values per cabinet type.
// Pure data — no logic. Modify this file to tune type-specific defaults.
//
// Dimension keys:
//   cm / in   — dimension values in each unit system
// Toe kick:
//   height_cm / height_in, depth_cm / depth_in
// Construction:
//   *_cm / *_in for unit-sensitive numeric fields
// Config:
//   Array of { type, items: [{ type }] } — groups and their items
// Doors / Drawers:
//   shape, handle — IDs from the preset arrays in constants.js
//   null = no initial selection
// Materials:
//   keyed by surface; value is a preset ID from MATERIAL_PRESETS, or null
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Granularity (step increment) for every dimension input, keyed by unit.
// Used by cabinet-init.js when applying defaults and on unit changes.
// Replaces unit_defaults.js — all dimension data now lives in this file.
// ---------------------------------------------------------------------------
const DIMENSION_STEPS = {
  cm: {
    "cabinet-width": 1,
    "cabinet-height": 1,
    "cabinet-depth": 1,
    "cabinet-height-from-floor": 1,
    "cabinet-total-height": 1,
    "toe-kick-height": 1,
    "toe-kick-depth": 1,
    "panel-thickness": 0.1,
    "back-panel-thickness": 0.1,
    "back-panel-recess": 0.1,
    "back-groove-depth": 0.1,
    "back-groove-clearance": 0.1,
    "stretcher-width": 0.1,
    "overlay-clearance": 0.1,
    "item-height": 1,
    "door-handle-offset-h": 0.1,
    "door-handle-offset-v": 0.1,
    "door-handle-rotation": 1,
    "drawer-handle-offset-h": 0.1,
    "drawer-handle-offset-v": 0.1,
    "drawer-handle-rotation": 1,
  },
  in: {
    "cabinet-width": 0.125,
    "cabinet-height": 0.125,
    "cabinet-depth": 0.125,
    "cabinet-height-from-floor": 0.125,
    "cabinet-total-height": 0.125,
    "toe-kick-height": 0.125,
    "toe-kick-depth": 0.125,
    "panel-thickness": 0.0625,
    "back-panel-thickness": 0.0625,
    "back-panel-recess": 0.0625,
    "back-groove-depth": 0.0625,
    "back-groove-clearance": 0.03125,
    "stretcher-width": 0.0625,
    "overlay-clearance": 0.0625,
    "item-height": 0.125,
    "door-handle-offset-h": 0.0625,
    "door-handle-offset-v": 0.0625,
    "door-handle-rotation": 1,
    "drawer-handle-offset-h": 0.0625,
    "drawer-handle-offset-v": 0.0625,
    "drawer-handle-rotation": 1,
  },
};

const CABINET_DEFAULTS = {
  // ── Base Cabinet ─────────────────────────────────────────────────────────
  base: {
    name: "Base Cabinet",
    dimensions: {
      cm: { width: 60, height: 87, depth: 58, heightFromFloor: 0 },
      in: { width: 24, height: 34, depth: 23, heightFromFloor: 0 },
    },
    toeKick: {
      enabled: true,
      height_cm: 10,
      height_in: 4,
      depth_cm: 5,
      depth_in: 2,
      skirting: true,
      createLegs: false,
      flatSides: true,
      flatBack: true,
      legs: null,
    },
    construction: {
      topPanel: "open",
      basePanel: "closed",
      sidePanels: "overlay",
      panelThickness_cm: 1.8,
      panelThickness_in: 0.75,
      backPanelType: "stretchers",
      backPanelThickness_cm: 0.8,
      backPanelThickness_in: 0.25,
      backPanelRecess_cm: 0,
      backPanelRecess_in: 0,
      stretcherCount: 2,
      stretcherWidth_cm: 12.0,
      stretcherWidth_in: 4.75,
      overlayType: "full",
      overlayClearance_cm: 0.1,
      overlayClearance_in: 0.0625,
    },
    config: [
      {
        type: "vertical-group",
        items: [
          {
            type: "door-hinge-right",
            height_cm: 0,
            height_in: 0,
            shelvesCount: 1,
          },
        ],
      },
    ],
    doors: {
      shape: "DW-101",
      handle: null,
    },
    drawers: {
      shape: "DW-101",
      handle: null,
    },
    panels: {
      shape: "DW-101",
    },
    materials: {
      carcass: "Alpine_White",
      panel: "WD-101",
      edge: "MT-W01",
      door: "WD-101",
      drawer: "WD-101",
      handle: "Matte_Black",
      glass: "Clear_Glass",
    },
  },

  // ── Wall Cabinet ──────────────────────────────────────────────────────────
  wall: {
    name: "Wall Cabinet",
    dimensions: {
      cm: { width: 60, height: 60, depth: 30, heightFromFloor: 165 },
      in: { width: 24, height: 24, depth: 12, heightFromFloor: 65 },
    },
    toeKick: {
      enabled: false,
      height_cm: 0,
      height_in: 0,
      depth_cm: 0,
      depth_in: 0,
      skirting: false,
      createLegs: false,
      flatSides: true,
      flatBack: true,
      legs: null,
    },
    construction: {
      topPanel: "closed",
      basePanel: "closed",
      sidePanels: "overlay",
      panelThickness_cm: 1.8,
      panelThickness_in: 0.75,
      backPanelType: "closed",
      backPanelThickness_cm: 0.8,
      backPanelThickness_in: 0.25,
      backPanelRecess_cm: 0,
      backPanelRecess_in: 0,
      stretcherCount: 2,
      stretcherWidth_cm: 12.0,
      stretcherWidth_in: 4.75,
      overlayType: "full",
      overlayClearance_cm: 0.1,
      overlayClearance_in: 0.0625,
    },
    config: [
      {
        type: "vertical-group",
        items: [
          {
            type: "door-hinge-right",
            height_cm: 0,
            height_in: 0,
            shelvesCount: 1,
          },
        ],
      },
    ],
    doors: {
      shape: "DW-101",
      handle: null,
    },
    drawers: {
      shape: "DW-101",
      handle: null,
    },
    panels: {
      shape: "DW-101",
    },
    materials: {
      carcass: "Alpine_White",
      panel: "WD-101",
      edge: "MT-W01",
      door: "WD-101",
      drawer: "WD-101",
      handle: "Matte_Black",
      glass: "Clear_Glass",
    },
  },

  // ── Tall Cabinet ──────────────────────────────────────────────────────────
  tall: {
    name: "Tall Cabinet",
    dimensions: {
      cm: { width: 60, height: 225, depth: 58, heightFromFloor: 0 },
      in: { width: 24, height: 88.5, depth: 23, heightFromFloor: 0 },
    },
    toeKick: {
      enabled: true,
      height_cm: 10,
      height_in: 4,
      depth_cm: 5,
      depth_in: 2,
      skirting: true,
      createLegs: false,
      flatSides: true,
      flatBack: true,
      legs: null,
    },
    construction: {
      topPanel: "closed",
      basePanel: "closed",
      sidePanels: "overlay",
      panelThickness_cm: 1.8,
      panelThickness_in: 0.75,
      backPanelType: "closed",
      backPanelThickness_cm: 0.8,
      backPanelThickness_in: 0.25,
      backPanelRecess_cm: 0,
      backPanelRecess_in: 0,
      stretcherCount: 2,
      stretcherWidth_cm: 12.0,
      stretcherWidth_in: 4.75,
      overlayType: "full",
      overlayClearance_cm: 0.1,
      overlayClearance_in: 0.0625,
    },
    config: [
      {
        type: "vertical-group",
        items: [
          {
            type: "door-hinge-right",
            height_cm: 0,
            height_in: 0,
            shelvesCount: 1,
          },
          { type: "separator", height_cm: 1.8, height_in: 0.709 },
          { type: "drawer", height_cm: 20, height_in: 8 },
          { type: "divider", height_cm: 1.8, height_in: 0.709 },
          {
            type: "door-hinge-right",
            height_cm: 0,
            height_in: 0,
            shelvesCount: 1,
          },
        ],
      },
    ],
    doors: {
      shape: "DW-101",
      handle: null,
    },
    drawers: {
      shape: "DW-101",
      handle: null,
    },
    panels: {
      shape: "DW-101",
    },
    materials: {
      carcass: "Alpine_White",
      panel: "WD-101",
      edge: "MT-W01",
      door: "WD-101",
      drawer: "WD-101",
      handle: "Matte_Black",
      glass: "Clear_Glass",
    },
  },

  // ── High Cabinet ──────────────────────────────────────────────────────────
  high: {
    name: "High Cabinet",
    dimensions: {
      cm: { width: 60, height: 40, depth: 58, heightFromFloor: 225 },
      in: { width: 24, height: 16, depth: 23, heightFromFloor: 88.5 },
    },
    toeKick: {
      enabled: false,
      height_cm: 0,
      height_in: 0,
      depth_cm: 0,
      depth_in: 0,
      skirting: false,
      createLegs: false,
      flatSides: true,
      flatBack: true,
      legs: null,
    },
    construction: {
      topPanel: "closed",
      basePanel: "closed",
      sidePanels: "overlay",
      panelThickness_cm: 1.8,
      panelThickness_in: 0.75,
      backPanelType: "closed",
      backPanelThickness_cm: 0.8,
      backPanelThickness_in: 0.25,
      backPanelRecess_cm: 0,
      backPanelRecess_in: 0,
      stretcherCount: 2,
      stretcherWidth_cm: 12.0,
      stretcherWidth_in: 4.75,
      overlayType: "full",
      overlayClearance_cm: 0.1,
      overlayClearance_in: 0.0625,
    },
    config: [
      {
        type: "vertical-group",
        items: [{ type: "door-hinge-top", height_cm: 0, height_in: 0 }],
      },
    ],
    doors: {
      shape: "DW-101",
      handle: null,
    },
    drawers: { shape: null, handle: null },
    panels: {
      shape: "DW-101",
    },
    materials: {
      carcass: "Alpine_White",
      panel: "WD-101",
      edge: "MT-W01",
      door: "WD-101",
      drawer: "WD-101",
      handle: "Matte_Black",
      glass: "Clear_Glass",
    },
  },

  // ── Base Corner Cabinet ───────────────────────────────────────────────────
  "base-corner": {
    name: "Base Corner Cabinet",
    cornerType: "l-shaped",
    accessibleSide: "right",
    dimensions: {
      cm: { width: 45, height: 87, depth: 58, heightFromFloor: 0 },
      in: { width: 18, height: 34, depth: 23, heightFromFloor: 0 },
    },
    toeKick: {
      enabled: true,
      height_cm: 10,
      height_in: 4,
      depth_cm: 5,
      depth_in: 2,
      skirting: true,
      createLegs: false,
      flatSides: true,
      flatBack: true,
      legs: null,
    },
    construction: {
      topPanel: "open",
      basePanel: "closed",
      sidePanels: "overlay",
      panelThickness_cm: 1.8,
      panelThickness_in: 0.75,
      backPanelType: "stretchers",
      backPanelThickness_cm: 0.8,
      backPanelThickness_in: 0.25,
      backPanelRecess_cm: 0,
      backPanelRecess_in: 0,
      stretcherCount: 2,
      stretcherWidth_cm: 12.0,
      stretcherWidth_in: 4.75,
      overlayType: "full",
      overlayClearance_cm: 0.1,
      overlayClearance_in: 0.0625,
    },
    config: [
      {
        type: "vertical-group",
        items: [{ type: "door-hinge-right", height_cm: 0, height_in: 0 }],
      },
    ],
    doors: {
      shape: "DW-101",
      handle: null,
    },
    drawers: { shape: "DW-101", handle: null },
    panels: {
      shape: "DW-101",
    },
    materials: {
      carcass: "Alpine_White",
      panel: "WD-101",
      edge: "MT-W01",
      door: "WD-101",
      drawer: "WD-101",
      handle: "Matte_Black",
      glass: "Clear_Glass",
    },
  },

  // ── Wall Corner Cabinet ───────────────────────────────────────────────────
  "wall-corner": {
    name: "Wall Corner Cabinet",
    cornerType: "l-shaped",
    accessibleSide: "right",
    dimensions: {
      cm: { width: 45, height: 60, depth: 30, heightFromFloor: 145 },
      in: { width: 18, height: 24, depth: 12, heightFromFloor: 57 },
    },
    toeKick: {
      enabled: false,
      height_cm: 0,
      height_in: 0,
      depth_cm: 0,
      depth_in: 0,
      skirting: false,
      createLegs: false,
      flatSides: true,
      flatBack: true,
      legs: null,
    },
    construction: {
      topPanel: "closed",
      basePanel: "closed",
      sidePanels: "overlay",
      panelThickness_cm: 1.8,
      panelThickness_in: 0.75,
      backPanelType: "closed",
      backPanelThickness_cm: 0.8,
      backPanelThickness_in: 0.25,
      backPanelRecess_cm: 0,
      backPanelRecess_in: 0,
      stretcherCount: 2,
      stretcherWidth_cm: 12.0,
      stretcherWidth_in: 4.75,
      overlayType: "full",
      overlayClearance_cm: 0.1,
      overlayClearance_in: 0.0625,
    },
    config: [
      {
        type: "vertical-group",
        items: [{ type: "door-hinge-right", height_cm: 0, height_in: 0 }],
      },
    ],
    doors: {
      shape: "DW-101",
      handle: null,
    },
    drawers: { shape: "DW-101", handle: null },
    panels: {
      shape: "DW-101",
    },
    materials: {
      carcass: "Alpine_White",
      panel: "WD-101",
      edge: "MT-W01",
      door: "WD-101",
      drawer: "WD-101",
      handle: "Matte_Black",
      glass: "Clear_Glass",
    },
  },

  // ── Filler ────────────────────────────────────────────────────────────────
  filler: {
    name: "Filler",
    dimensions: {
      cm: { width: 12, height: 87, depth: 58, heightFromFloor: 0 },
      in: { width: 4.75, height: 34.25, depth: 23, heightFromFloor: 0 },
    },
    toeKick: {
      enabled: true,
      height_cm: 10,
      height_in: 4,
      depth_cm: 5,
      depth_in: 2,
      skirting: true,
      createLegs: false,
      flatSides: true,
      flatBack: true,
      legs: null,
    },
    construction: {
      topPanel: "closed",
      basePanel: "closed",
      sidePanels: "overlay",
      panelThickness_cm: 1.8,
      panelThickness_in: 0.75,
      backPanelType: "closed",
      backPanelThickness_cm: 0.8,
      backPanelThickness_in: 0.25,
      backPanelRecess_cm: 2,
      backPanelRecess_in: 0.75,
      stretcherCount: 2,
      stretcherWidth_cm: 12.0,
      stretcherWidth_in: 4.75,
      overlayType: "full",
      overlayClearance_cm: 0.1,
      overlayClearance_in: 0.0625,
    },
    config: [
      {
        type: "vertical-group",
        items: [{ type: "panel", height_cm: 0, height_in: 0 }],
      },
    ],
    doors: { shape: "DW-101", handle: null },
    drawers: { shape: "DW-101", handle: null },
    panels: {
      shape: "DW-101",
    },
    materials: {
      carcass: "Alpine_White",
      panel: "WD-101",
      edge: "MT-W01",
      door: "WD-101",
      drawer: "WD-101",
      handle: "Matte_Black",
      glass: "Clear_Glass",
    },
  },
};
