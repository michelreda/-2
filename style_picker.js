// Style Picker — Filter Dialog JS
// Accordion with section/item checkboxes. Sends checked keys to Ruby.

(function () {
  "use strict";

  // ---------------------------------------------------------------------------
  // DOM cache
  // ---------------------------------------------------------------------------

  const UI = {};

  function cacheDOM() {
    UI.sourceLabel = document.getElementById("source-label");
    UI.btnCancel = document.getElementById("btn-cancel");
    UI.btnApply = document.getElementById("btn-apply");
    UI.sections = document.querySelectorAll(".filter-section");
  }

  // ---------------------------------------------------------------------------
  // Accordion toggle
  // ---------------------------------------------------------------------------

  function initAccordion() {
    UI.sections.forEach((section) => {
      const header = section.querySelector(".filter-header");
      const body = section.querySelector(".filter-body");
      const icon = header.querySelector(".toggle-icon");

      // Click anywhere on the header (except the checkbox) toggles collapse
      header.addEventListener("click", (e) => {
        if (e.target.classList.contains("section-checkbox")) return;
        const isOpen = body.classList.toggle("open");
        icon.innerHTML = isOpen ? "&#9662;" : "&#9656;";
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Checkbox logic
  // ---------------------------------------------------------------------------

  function initCheckboxes() {
    UI.sections.forEach((section) => {
      const sectionCb = section.querySelector(".section-checkbox");
      const itemCbs = section.querySelectorAll(
        '.filter-body input[type="checkbox"]',
      );

      // Section checkbox → toggle all children
      sectionCb.addEventListener("change", () => {
        itemCbs.forEach((cb) => (cb.checked = sectionCb.checked));
      });

      // Child checkbox → update section state
      itemCbs.forEach((cb) => {
        cb.addEventListener("change", () => {
          _updateSectionCheckbox(sectionCb, itemCbs);
        });
      });
    });
  }

  function _updateSectionCheckbox(sectionCb, itemCbs) {
    const total = itemCbs.length;
    let checked = 0;
    itemCbs.forEach((cb) => {
      if (cb.checked) checked++;
    });
    if (checked === 0) {
      sectionCb.checked = false;
      sectionCb.indeterminate = false;
    } else if (checked === total) {
      sectionCb.checked = true;
      sectionCb.indeterminate = false;
    } else {
      sectionCb.checked = false;
      sectionCb.indeterminate = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Collect checked filter
  // ---------------------------------------------------------------------------

  function collectFilter() {
    const filter = {};
    UI.sections.forEach((section) => {
      const sectionKey = section.dataset.section;
      const itemCbs = section.querySelectorAll(
        '.filter-body input[type="checkbox"]',
      );
      const keys = [];
      itemCbs.forEach((cb) => {
        if (cb.checked) keys.push(cb.dataset.key);
      });
      if (keys.length > 0) {
        filter[sectionKey] = keys;
      }
    });
    return filter;
  }

  // ---------------------------------------------------------------------------
  // Buttons
  // ---------------------------------------------------------------------------

  function initButtons() {
    UI.btnCancel.addEventListener("click", () => {
      sketchup.cancel_filter();
    });

    UI.btnApply.addEventListener("click", () => {
      const filter = collectFilter();
      sketchup.confirm_filter(JSON.stringify(filter));
    });
  }

  // ---------------------------------------------------------------------------
  // Ruby → JS bridge
  // ---------------------------------------------------------------------------

  window.initFilter = function (raw) {
    const data = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (data.source_name || data.source_type) {
      const parts = [];
      if (data.source_type) parts.push(data.source_type);
      if (data.source_name) parts.push(data.source_name);
      UI.sourceLabel.textContent = parts.join(" — ");
    }
  };

  window.restoreFilter = function (raw) {
    const filter = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!filter || typeof filter !== "object") return;

    // First uncheck everything
    UI.sections.forEach((section) => {
      const itemCbs = section.querySelectorAll(
        '.filter-body input[type="checkbox"]',
      );
      itemCbs.forEach((cb) => (cb.checked = false));
    });

    // Then check only the keys present in the filter
    UI.sections.forEach((section) => {
      const sectionKey = section.dataset.section;
      const sectionCb = section.querySelector(".section-checkbox");
      const itemCbs = section.querySelectorAll(
        '.filter-body input[type="checkbox"]',
      );
      const keys = filter[sectionKey] || [];

      itemCbs.forEach((cb) => {
        cb.checked = keys.includes(cb.dataset.key);
      });

      _updateSectionCheckbox(sectionCb, itemCbs);
    });
  };

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  document.addEventListener("DOMContentLoaded", () => {
    cacheDOM();
    initAccordion();
    initCheckboxes();
    initButtons();
    sketchup.dialog_ready();
  });
})();
