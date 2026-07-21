// schedule_manager.js
// Cabinet Schedule Manager — ML Cabinets
// Ported from ML_Kitchens ScheduleManager; adapted for ML_Cabinets data shape.

"use strict";

class ScheduleManager {
  constructor() {
    this.data = [];
    this.filteredData = [];
    this.sortColumn = null;
    this.sortDirection = "asc";
    this.filters = {};
    this.unitSystem = "metric";
    this.unitLabel = "cm";

    this.currentFilterColumn = null;

    this.preferences = {
      columnVisibility: {},
      rowDensity: "normal",
      sortColumn: null,
      sortDirection: "asc",
      filters: {},
    };

    // ── Column definitions ──────────────────────────────────────────────────
    this.columns = [
      {
        key: "row_num",
        label: "#",
        sortable: false,
        filterable: false,
        width: "44px",
      },
      {
        key: "thumbnail",
        label: "Preview",
        sortable: false,
        filterable: false,
        width: "96px",
      },
      {
        key: "name",
        label: "Name",
        sortable: true,
        filterable: true,
        filterType: "text",
        editable: true,
      },
      {
        key: "id",
        label: "ID",
        sortable: true,
        filterable: true,
        filterType: "text",
        width: "180px",
      },
      {
        key: "category",
        label: "Category",
        sortable: true,
        filterable: true,
        filterType: "checkbox",
        width: "130px",
      },
      {
        key: "quantity",
        label: "Qty",
        sortable: true,
        filterable: true,
        filterType: "numeric",
        type: "number",
        width: "64px",
      },
      {
        key: "price",
        label: "Unit Price",
        sortable: true,
        filterable: true,
        filterType: "numeric",
        type: "number",
        editable: true,
        width: "110px",
      },
      {
        key: "subtotal",
        label: "Subtotal",
        sortable: true,
        filterable: false,
        type: "number",
        width: "110px",
      },
      {
        key: "width",
        label: "Width",
        labelSuffix: true,
        sortable: true,
        filterable: true,
        filterType: "numeric",
        type: "number",
        width: "90px",
      },
      {
        key: "height",
        label: "Height",
        labelSuffix: true,
        sortable: true,
        filterable: true,
        filterType: "numeric",
        type: "number",
        width: "90px",
      },
      {
        key: "depth",
        label: "Depth",
        labelSuffix: true,
        sortable: true,
        filterable: true,
        filterType: "numeric",
        type: "number",
        width: "90px",
      },
      {
        key: "door_count",
        label: "Doors",
        sortable: true,
        filterable: true,
        type: "number",
        width: "72px",
      },
      {
        key: "drawer_count",
        label: "Drawers",
        sortable: true,
        filterable: true,
        type: "number",
        width: "72px",
      },
      {
        key: "shelf_count",
        label: "Shelves",
        sortable: true,
        filterable: true,
        type: "number",
        width: "72px",
      },
    ];

    this._init();
  }

  // ── Column label helper ───────────────────────────────────────────────────

  getColumnLabel(col) {
    return col.labelSuffix ? `${col.label} (${this.unitLabel})` : col.label;
  }

  // ── Unit system ───────────────────────────────────────────────────────────

  setUnitSystem(unitInfo) {
    this.unitSystem = unitInfo.system;
    this.unitLabel = unitInfo.label;
    if (this.data.length > 0) this.renderTable();
  }

  // ── Initialization ────────────────────────────────────────────────────────

  _init() {
    this._bindEvents();
    this.loadPreferences(null); // apply default visibility before data loads
    if (typeof sketchup !== "undefined") {
      sketchup.getUnitSystem();
      sketchup.getPreferences();
      sketchup.getScheduleData();
      sketchup.getClientInfo();
    }
  }

  _bindEvents() {
    document
      .getElementById("refreshBtn")
      .addEventListener("click", () => this.refresh());
    document
      .getElementById("exportBtn")
      .addEventListener("click", () => this.showExportModal());
    document
      .getElementById("columnsBtn")
      .addEventListener("click", () => this.showColumnsModal());
    document
      .getElementById("densityBtn")
      .addEventListener("click", () => this.showDensityModal());
    document
      .getElementById("filtersBtn")
      .addEventListener("click", () => this._updateFilterUI());
    document
      .getElementById("clearAllFiltersBtn")
      .addEventListener("click", () => this.clearAllFilters());

    // Export modal
    document
      .getElementById("exportModalClose")
      .addEventListener("click", () => this._hideModal("exportModal"));
    document
      .getElementById("exportCancelBtn")
      .addEventListener("click", () => this._hideModal("exportModal"));
    document
      .getElementById("exportConfirmBtn")
      .addEventListener("click", () => this._doExport());

    // Columns modal
    document
      .getElementById("columnsModalClose")
      .addEventListener("click", () => this._hideModal("columnsModal"));
    document
      .getElementById("columnsResetBtn")
      .addEventListener("click", () => this._resetColumnVisibility());
    document
      .getElementById("columnsSaveBtn")
      .addEventListener("click", () => this._saveColumnVisibility());

    // Density modal
    document
      .getElementById("densityModalClose")
      .addEventListener("click", () => this._hideModal("densityModal"));
    document
      .getElementById("densitySaveBtn")
      .addEventListener("click", () => this._saveDensity());

    // Filter modal
    document
      .getElementById("filterModalClose")
      .addEventListener("click", () => this._hideFilterModal());
    document
      .getElementById("filterClearBtn")
      .addEventListener("click", () => this._clearCurrentFilter());
    document
      .getElementById("filterApplyBtn")
      .addEventListener("click", () => this._applyCurrentFilter());

    // Client info
    document
      .getElementById("clientInfoToggle")
      .addEventListener("click", () => this._toggleClientInfo());
    document
      .getElementById("saveClientInfoBtn")
      .addEventListener("click", () => this.saveClientInfo());
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  loadScheduleData(data) {
    this.data = data;
    this._applyFiltersAndSort();
    this.renderTable();
    this._updateStats();
    this._updateFilterUI();
    this._hideLoading();
  }

  refresh() {
    this._showLoading();
    if (typeof sketchup !== "undefined") sketchup.getScheduleData();
  }

  // ── Filter & Sort ──────────────────────────────────────────────────────────

  _applyFiltersAndSort() {
    this.filteredData = this.data.filter((row) => {
      for (const key in this.filters) {
        const filterValue = this.filters[key];
        if (!filterValue && filterValue !== 0) continue;

        if (Array.isArray(filterValue)) {
          if (filterValue.length === 0) continue;
          if (!filterValue.includes(String(row[key] ?? ""))) return false;
        } else if (
          typeof filterValue === "object" &&
          filterValue.operator &&
          filterValue.value !== undefined
        ) {
          const cell = parseFloat(row[key]);
          const compare = parseFloat(filterValue.value);
          if (isNaN(cell) || isNaN(compare)) continue;
          const { operator } = filterValue;
          if (operator === "==" && !(cell === compare)) return false;
          if (operator === "!=" && !(cell !== compare)) return false;
          if (operator === "<" && !(cell < compare)) return false;
          if (operator === "<=" && !(cell <= compare)) return false;
          if (operator === ">" && !(cell > compare)) return false;
          if (operator === ">=" && !(cell >= compare)) return false;
        } else {
          const text = String(filterValue).toLowerCase();
          if (!text) continue;
          if (
            !String(row[key] ?? "")
              .toLowerCase()
              .includes(text)
          )
            return false;
        }
      }
      return true;
    });

    if (this.sortColumn) {
      this.filteredData.sort((a, b) => {
        let av = a[this.sortColumn];
        let bv = b[this.sortColumn];
        if (av == null) return 1;
        if (bv == null) return -1;
        if (typeof av === "number" && typeof bv === "number") {
          return this.sortDirection === "asc" ? av - bv : bv - av;
        }
        av = String(av).toLowerCase();
        bv = String(bv).toLowerCase();
        if (av < bv) return this.sortDirection === "asc" ? -1 : 1;
        if (av > bv) return this.sortDirection === "asc" ? 1 : -1;
        return 0;
      });
    }
  }

  setSort(column) {
    if (this.sortColumn === column) {
      this.sortDirection = this.sortDirection === "asc" ? "desc" : "asc";
    } else {
      this.sortColumn = column;
      this.sortDirection = "asc";
    }
    this.preferences.sortColumn = this.sortColumn;
    this.preferences.sortDirection = this.sortDirection;
    this._applyFiltersAndSort();
    this.renderTable();
    this._savePreferences();
  }

  // ── Filter modals ─────────────────────────────────────────────────────────

  showFilterModal(columnKey) {
    const col = this.columns.find((c) => c.key === columnKey);
    if (!col || !col.filterable) return;

    this.currentFilterColumn = columnKey;
    document.getElementById("filterModalTitle").textContent =
      `Filter: ${this.getColumnLabel(col)}`;

    const content = document.getElementById("filterModalContent");
    if (col.filterType === "checkbox") {
      content.innerHTML = this._buildCheckboxFilter(columnKey);
      setTimeout(() => {
        const all = document.getElementById("smSelectAllFilter");
        if (all) {
          all.addEventListener("change", (e) => {
            document.querySelectorAll(".sm-filter-cb").forEach((cb) => {
              cb.checked = e.target.checked;
            });
          });
        }
      }, 0);
    } else if (col.filterType === "numeric") {
      content.innerHTML = this._buildNumericFilter(columnKey);
    } else {
      content.innerHTML = this._buildTextFilter(columnKey);
    }

    document.getElementById("filterModal").style.display = "flex";
  }

  _hideFilterModal() {
    document.getElementById("filterModal").style.display = "none";
    this.currentFilterColumn = null;
  }

  _buildTextFilter(key) {
    const val = this.filters[key] || "";
    return `<input type="text" class="sm-filter-input" id="smFilterText"
              placeholder="Enter filter text…" value="${val}">`;
  }

  _buildNumericFilter(key) {
    const cur = this.filters[key] || { operator: "==", value: "" };
    const op = cur.operator || "==";
    const val = cur.value ?? "";
    return `
      <div class="sm-numeric-filter">
        <div>
          <label style="display:block;margin-bottom:6px;font-weight:600;font-size:12px;">Comparison</label>
          <select id="smNumericOp" class="sm-filter-input">
            <option value="=="  ${op === "==" ? "selected" : ""}>= Equal to</option>
            <option value="!="  ${op === "!=" ? "selected" : ""}>&ne; Not equal to</option>
            <option value="<"   ${op === "<" ? "selected" : ""}>&lt; Less than</option>
            <option value="<="  ${op === "<=" ? "selected" : ""}>&le; Less than or equal to</option>
            <option value=">"   ${op === ">" ? "selected" : ""}>&gt; Greater than</option>
            <option value=">="  ${op === ">=" ? "selected" : ""}>&ge; Greater than or equal to</option>
          </select>
        </div>
        <div>
          <label style="display:block;margin-bottom:6px;font-weight:600;font-size:12px;">Value</label>
          <input type="number" step="any" class="sm-filter-input" id="smNumericVal"
                 placeholder="Enter value…" value="${val}">
        </div>
      </div>`;
  }

  _buildCheckboxFilter(key) {
    const uniqueVals = [...new Set(this.data.map((r) => String(r[key] ?? "")))]
      .filter(Boolean)
      .sort();
    const currentFilter = this.filters[key] || [];
    const allChecked =
      currentFilter.length === 0 || currentFilter.length === uniqueVals.length;

    let html = `<div class="sm-filter-select-all">
      <label class="sm-filter-option">
        <input type="checkbox" id="smSelectAllFilter" ${allChecked ? "checked" : ""}>
        <span>Select All</span>
      </label></div>
      <div class="sm-filter-options">`;

    uniqueVals.forEach((v) => {
      const checked = currentFilter.length === 0 || currentFilter.includes(v);
      html += `<label class="sm-filter-option">
        <input type="checkbox" class="sm-filter-cb" value="${v}" ${checked ? "checked" : ""}>
        <span>${v}</span>
      </label>`;
    });
    html += `</div>`;
    return html;
  }

  _clearCurrentFilter() {
    if (!this.currentFilterColumn) return;
    delete this.filters[this.currentFilterColumn];
    this.preferences.filters = this.filters;
    this._applyFiltersAndSort();
    this.renderTable();
    this._updateFilterUI();
    this._savePreferences();
    this._hideFilterModal();
  }

  _applyCurrentFilter() {
    if (!this.currentFilterColumn) return;
    const col = this.columns.find((c) => c.key === this.currentFilterColumn);

    if (col.filterType === "checkbox") {
      const checked = Array.from(
        document.querySelectorAll(".sm-filter-cb:checked"),
      ).map((cb) => cb.value);
      const total = this._uniqueValues(this.currentFilterColumn).length;
      if (checked.length > 0 && checked.length < total) {
        this.filters[this.currentFilterColumn] = checked;
      } else {
        delete this.filters[this.currentFilterColumn];
      }
    } else if (col.filterType === "numeric") {
      const opEl = document.getElementById("smNumericOp");
      const valEl = document.getElementById("smNumericVal");
      if (valEl && valEl.value.trim() !== "") {
        this.filters[this.currentFilterColumn] = {
          operator: opEl.value,
          value: parseFloat(valEl.value),
        };
      } else {
        delete this.filters[this.currentFilterColumn];
      }
    } else {
      const el = document.getElementById("smFilterText");
      if (el && el.value.trim()) {
        this.filters[this.currentFilterColumn] = el.value.trim();
      } else {
        delete this.filters[this.currentFilterColumn];
      }
    }

    this.preferences.filters = this.filters;
    this._applyFiltersAndSort();
    this.renderTable();
    this._updateFilterUI();
    this._savePreferences();
    this._hideFilterModal();
  }

  clearAllFilters() {
    this.filters = {};
    this.preferences.filters = {};
    this._applyFiltersAndSort();
    this.renderTable();
    this._updateFilterUI();
    this._savePreferences();
  }

  _uniqueValues(key) {
    return [...new Set(this.data.map((r) => r[key]))].filter((v) => v != null);
  }

  _updateFilterUI() {
    const count = Object.keys(this.filters).length;
    const badge = document.getElementById("filterBadge");
    const clearBtn = document.getElementById("clearAllFiltersBtn");

    if (count > 0) {
      badge.textContent = count;
      badge.style.display = "inline-flex";
      clearBtn.style.display = "inline-flex";
      document.getElementById("totalCabinetsLabel").textContent =
        "TOTAL CABINETS (FILTERED)";
      document.getElementById("uniqueConfigsLabel").textContent =
        "UNIQUE CONFIGURATIONS (FILTERED)";
      document.getElementById("totalValueLabel").textContent =
        "TOTAL VALUE (FILTERED)";
    } else {
      badge.style.display = "none";
      clearBtn.style.display = "none";
      document.getElementById("totalCabinetsLabel").textContent =
        "TOTAL CABINETS";
      document.getElementById("uniqueConfigsLabel").textContent =
        "UNIQUE CONFIGURATIONS";
      document.getElementById("totalValueLabel").textContent = "TOTAL VALUE";
    }
  }

  // ── Table Rendering ───────────────────────────────────────────────────────

  renderTable() {
    const headerRow = document.getElementById("tableHeader");
    const tbody = document.getElementById("tableBody");
    headerRow.innerHTML = "";
    tbody.innerHTML = "";

    const cols = this._visibleColumns();
    if (cols.length === 0) {
      this._showEmpty("No columns selected");
      return;
    }

    // Headers
    cols.forEach((col) => {
      const th = document.createElement("th");
      if (col.width) th.style.width = col.width;

      const labelSpan = document.createElement("span");
      labelSpan.className = "sm-sort-indicator";
      labelSpan.textContent = this.getColumnLabel(col);
      if (col.filterable) labelSpan.style.paddingRight = "26px";
      th.appendChild(labelSpan);

      if (col.filterable) {
        const fi = document.createElement("span");
        fi.className = "sm-filter-icon";
        fi.textContent = "▾";
        fi.title = "Filter";
        if (this.filters[col.key]) fi.classList.add("active");
        fi.addEventListener("click", (e) => {
          e.stopPropagation();
          this.showFilterModal(col.key);
        });
        th.appendChild(fi);
      }

      if (col.sortable) {
        th.classList.add("sortable");
        if (this.sortColumn === col.key) {
          th.classList.add(
            this.sortDirection === "asc" ? "sorted-asc" : "sorted-desc",
          );
        }
        labelSpan.style.cursor = "pointer";
        labelSpan.addEventListener("click", () => this.setSort(col.key));
      }

      headerRow.appendChild(th);
    });

    // Rows
    if (this.filteredData.length === 0) {
      this._showEmpty("No cabinets match the current filters");
      return;
    }

    this.filteredData.forEach((row, index) => {
      const tr = document.createElement("tr");
      tr.dataset.fingerprint = row.fingerprint;

      cols.forEach((col) => {
        const td = document.createElement("td");

        if (col.key === "row_num") {
          td.textContent = index + 1;
          td.classList.add("sm-row-num");
        } else if (col.key === "thumbnail") {
          if (row.thumbnail) {
            const img = document.createElement("img");
            img.src = row.thumbnail;
            img.className = "sm-thumb";
            img.alt = row.name || "Cabinet";
            td.appendChild(img);
          } else {
            const ph = document.createElement("div");
            ph.className = "sm-thumb-placeholder";
            ph.textContent = "▪";
            td.appendChild(ph);
          }
        } else {
          const value = row[col.key];
          if (col.type === "number" && value != null) {
            if (col.key === "price" || col.key === "subtotal") {
              td.textContent = "$" + Number(value).toFixed(2);
            } else if (
              col.key === "width" ||
              col.key === "height" ||
              col.key === "depth"
            ) {
              td.textContent = Number(value).toFixed(
                this.unitSystem === "imperial" ? 3 : 1,
              );
            } else {
              td.textContent = value;
            }
            td.classList.add("sm-num");
          } else {
            td.textContent = value ?? "";
          }

          if (col.editable) {
            td.classList.add("sm-editable");
            td.addEventListener("dblclick", () =>
              this._editCell(td, row, col.key),
            );
          }
        }

        tr.appendChild(td);
      });

      tr.addEventListener("click", (e) => {
        if (!e.target.classList.contains("sm-editable-input")) {
          // Highlight row
          document
            .querySelectorAll(".sm-table tbody tr")
            .forEach((r) => r.classList.remove("sm-selected"));
          tr.classList.add("sm-selected");
          this._selectInModel(row.instance_ids);
        }
      });

      tbody.appendChild(tr);
    });

    document.getElementById("emptyState").style.display = "none";
  }

  // ── Inline cell editing ───────────────────────────────────────────────────

  _editCell(td, row, key) {
    const original = row[key];
    td.classList.add("editing");
    td.innerHTML = "";

    const input = document.createElement("input");
    input.type = key === "price" ? "number" : "text";
    input.className = "sm-editable-input";
    input.value = original ?? "";
    if (key === "price") input.step = "0.01";
    td.appendChild(input);
    input.focus();
    input.select();

    const save = () => {
      const newVal = key === "price" ? parseFloat(input.value) : input.value;
      td.classList.remove("editing");
      if (newVal !== original) {
        if (key === "price") {
          this._updatePrice(row.fingerprint, newVal, row.instance_ids);
          td.textContent = "$" + Number(newVal).toFixed(2);
        } else if (key === "name") {
          this._updateName(row.fingerprint, newVal, row.instance_ids);
          td.textContent = newVal;
        }
        row[key] = newVal;
      } else {
        td.textContent =
          key === "price"
            ? "$" + Number(original).toFixed(2)
            : String(original ?? "");
      }
      td.classList.add("sm-editable");
      td.addEventListener("dblclick", () => this._editCell(td, row, key));
    };

    const cancel = () => {
      td.classList.remove("editing");
      td.textContent =
        key === "price"
          ? "$" + Number(original).toFixed(2)
          : String(original ?? "");
      td.classList.add("sm-editable");
      td.addEventListener("dblclick", () => this._editCell(td, row, key));
    };

    input.addEventListener("blur", save);
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") save();
      if (e.key === "Escape") cancel();
    });
  }

  // ── Ruby bridge calls ─────────────────────────────────────────────────────

  _updatePrice(fingerprint, price, instanceIds) {
    if (typeof sketchup !== "undefined") {
      sketchup.updatePrice(fingerprint, price, JSON.stringify(instanceIds));
    }
  }

  _updateName(fingerprint, name, instanceIds) {
    if (typeof sketchup !== "undefined") {
      sketchup.updateName(fingerprint, name, JSON.stringify(instanceIds));
    }
  }

  _selectInModel(instanceIds) {
    if (typeof sketchup !== "undefined") {
      sketchup.selectCabinets(JSON.stringify(instanceIds));
    }
  }

  // ── Column visibility ─────────────────────────────────────────────────────

  _visibleColumns() {
    return this.columns.filter(
      (col) => this.preferences.columnVisibility[col.key] !== false,
    );
  }

  showColumnsModal() {
    const list = document.getElementById("columnsList");
    list.innerHTML = "";

    this.columns.forEach((col) => {
      const label = document.createElement("label");
      label.className = "sm-column-item";

      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.checked = this.preferences.columnVisibility[col.key] !== false;
      cb.dataset.column = col.key;

      const span = document.createElement("span");
      span.textContent = this.getColumnLabel(col);

      label.appendChild(cb);
      label.appendChild(span);
      list.appendChild(label);
    });

    document.getElementById("columnsModal").style.display = "flex";

    document.querySelectorAll(".sm-preset-btn").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        document
          .querySelectorAll(".sm-preset-btn")
          .forEach((b) => b.classList.remove("active"));
        e.currentTarget.classList.add("active");
        this._applyColumnPreset(e.currentTarget.dataset.preset);
      });
    });

    const preset = this._detectPreset();
    if (preset) {
      const btn = document.querySelector(
        `.sm-preset-btn[data-preset="${preset}"]`,
      );
      if (btn) btn.classList.add("active");
    }
  }

  _detectPreset() {
    const visible = this.columns
      .filter((c) => this.preferences.columnVisibility[c.key] !== false)
      .map((c) => c.key);
    const minimal = [
      "row_num",
      "thumbnail",
      "name",
      "quantity",
      "price",
      "subtotal",
    ];
    const standard = [
      "row_num",
      "thumbnail",
      "name",
      "id",
      "category",
      "quantity",
      "price",
      "subtotal",
      "width",
      "height",
      "depth",
    ];
    if (visible.length === this.columns.length) return "all";
    if (
      JSON.stringify([...visible].sort()) ===
      JSON.stringify([...minimal].sort())
    )
      return "minimal";
    if (
      JSON.stringify([...visible].sort()) ===
      JSON.stringify([...standard].sort())
    )
      return "standard";
    return null;
  }

  _applyColumnPreset(preset) {
    const vis = {};
    this.columns.forEach((c) => {
      vis[c.key] = false;
    });

    const sets = {
      minimal: [
        "row_num",
        "thumbnail",
        "name",
        "category",
        "quantity",
        "price",
        "subtotal",
      ],
      standard: [
        "row_num",
        "thumbnail",
        "name",
        "id",
        "category",
        "quantity",
        "price",
        "subtotal",
        "width",
        "height",
        "depth",
      ],
      all: this.columns.map((c) => c.key),
    };
    (sets[preset] || []).forEach((k) => {
      vis[k] = true;
    });

    this.preferences.columnVisibility = vis;
    document
      .querySelectorAll("#columnsList input[type='checkbox']")
      .forEach((cb) => {
        cb.checked = vis[cb.dataset.column] !== false;
      });

    this.renderTable();
    this._savePreferences();
    this._hideModal("columnsModal");
  }

  _saveColumnVisibility() {
    document
      .querySelectorAll("#columnsList input[type='checkbox']")
      .forEach((cb) => {
        this.preferences.columnVisibility[cb.dataset.column] = cb.checked;
      });
    this.renderTable();
    this._savePreferences();
    this._hideModal("columnsModal");
  }

  _resetColumnVisibility() {
    this.columns.forEach((c) => {
      this.preferences.columnVisibility[c.key] = true;
    });
    this.renderTable();
    this._savePreferences();
    this._hideModal("columnsModal");
  }

  // ── Density ───────────────────────────────────────────────────────────────

  showDensityModal() {
    const current = this.preferences.rowDensity || "normal";
    const el = document.querySelector(
      `input[name='density'][value='${current}']`,
    );
    if (el) el.checked = true;
    document.getElementById("densityModal").style.display = "flex";
  }

  _saveDensity() {
    const el = document.querySelector("input[name='density']:checked");
    if (el) this._applyDensity(el.value);
    this._hideModal("densityModal");
  }

  _applyDensity(density) {
    this.preferences.rowDensity = density;
    const table = document.getElementById("scheduleTable");
    table.classList.remove("density-compact", "density-comfortable");
    if (density !== "normal") table.classList.add(`density-${density}`);
    this._savePreferences();
  }

  // ── Export ────────────────────────────────────────────────────────────────

  showExportModal() {
    document.getElementById("exportModal").style.display = "flex";
  }

  _doExport() {
    const format =
      document.querySelector("input[name='exportFormat']:checked")?.value ||
      "csv";
    const visible = this._visibleColumns();
    const exportCols =
      format === "csv" ? visible.filter((c) => c.key !== "thumbnail") : visible;
    if (typeof sketchup !== "undefined") {
      sketchup.exportSchedule(
        format,
        JSON.stringify(this.filteredData),
        JSON.stringify(exportCols),
      );
    }
    this._hideModal("exportModal");
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  _updateStats() {
    const unique = this.filteredData.length;
    const total = this.filteredData.reduce(
      (s, r) => s + (Number(r.quantity) || 0),
      0,
    );
    const value = this.filteredData.reduce(
      (s, r) => s + (Number(r.subtotal) || 0),
      0,
    );

    document.getElementById("totalCabinets").textContent = total;
    document.getElementById("uniqueConfigs").textContent = unique;
    document.getElementById("totalValue").textContent = "$" + value.toFixed(2);
    document.getElementById("generatedTime").textContent =
      new Date().toLocaleTimeString();

    document.getElementById("summaryText").textContent =
      `${unique} configuration${unique !== 1 ? "s" : ""}, ${total} total cabinet${total !== 1 ? "s" : ""}`;
    document.getElementById("footerQuantity").textContent = total;
    document.getElementById("footerTotal").textContent = "$" + value.toFixed(2);
  }

  // ── Preferences ───────────────────────────────────────────────────────────

  loadPreferences(savedPrefs) {
    const defaultVis = {};
    this.columns.forEach((c) => {
      defaultVis[c.key] = false;
    });
    [
      "row_num",
      "thumbnail",
      "name",
      "category",
      "quantity",
      "price",
      "subtotal",
      "width",
      "height",
      "depth",
    ].forEach((k) => {
      defaultVis[k] = true;
    });

    if (savedPrefs) {
      this.preferences = {
        columnVisibility: savedPrefs.columnVisibility || defaultVis,
        rowDensity: savedPrefs.rowDensity || "normal",
        sortColumn: savedPrefs.sortColumn || null,
        sortDirection: savedPrefs.sortDirection || "asc",
        filters: savedPrefs.filters || {},
      };
      this.sortColumn = this.preferences.sortColumn;
      this.sortDirection = this.preferences.sortDirection;
      this.filters = this.preferences.filters;
    } else {
      this.preferences = {
        columnVisibility: defaultVis,
        rowDensity: "normal",
        sortColumn: null,
        sortDirection: "asc",
        filters: {},
      };
    }

    this._applyDensity(this.preferences.rowDensity);
    this._updateFilterUI();
  }

  _savePreferences() {
    if (typeof sketchup !== "undefined") {
      sketchup.savePreferences(JSON.stringify(this.preferences));
    }
  }

  // ── Client Information ────────────────────────────────────────────────────

  _toggleClientInfo() {
    const content = document.getElementById("clientInfoContent");
    const icon = document.getElementById("clientToggleIcon");
    const collapsed = content.classList.contains("collapsed");
    content.classList.toggle("collapsed", !collapsed);
    icon.classList.toggle("collapsed", !collapsed);
  }

  loadClientInfo(info) {
    document.getElementById("clientName").value = info.name || "";
    document.getElementById("clientMobile").value = info.mobile || "";
    document.getElementById("clientEmail").value = info.email || "";
    document.getElementById("clientAddress").value = info.address || "";
  }

  saveClientInfo() {
    const info = {
      name: document.getElementById("clientName").value,
      mobile: document.getElementById("clientMobile").value,
      email: document.getElementById("clientEmail").value,
      address: document.getElementById("clientAddress").value,
    };
    if (typeof sketchup !== "undefined") {
      sketchup.saveClientInfo(JSON.stringify(info));
    }
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  _showLoading() {
    document.getElementById("loadingState").style.display = "flex";
    document.getElementById("emptyState").style.display = "none";
    document.getElementById("tableBody").innerHTML = "";
  }

  _hideLoading() {
    document.getElementById("loadingState").style.display = "none";
  }

  _showEmpty(message) {
    const el = document.getElementById("emptyState");
    const p = el.querySelector("p");
    if (p) p.textContent = message || "No cabinets found";
    el.style.display = "flex";
  }

  _hideModal(id) {
    const el = document.getElementById(id);
    if (el) el.style.display = "none";
  }

  showNotification(message, type = "info") {
    const el = document.getElementById("notification");
    document.getElementById("notificationText").textContent = message;
    el.className = `sm-notification${type !== "info" ? " " + type : ""}`;
    el.style.display = "block";
    setTimeout(() => {
      el.style.display = "none";
    }, 3500);
  }
}

// ── Global instance ─────────────────────────────────────────────────────────
window.scheduleManager = new ScheduleManager();

// ---------------------------------------------------------------------------
// License banner — Ruby → JS
// ---------------------------------------------------------------------------

window.setLicenseStatus = function (params) {
  var data = typeof params === "string" ? JSON.parse(params) : params;
  var banner = document.getElementById("license-banner");
  var text = document.getElementById("license-banner-text");
  var btn = document.getElementById("license-banner-btn");
  if (!banner) return;

  var state = data.state;
  if (!state || state === "licensed" || state === "licensed_permanent") {
    banner.hidden = true;
    return;
  }

  banner.className = "ml-license-banner";
  if (state === "trial") {
    banner.classList.add("ml-license-banner--trial");
    text.textContent =
      "Trial: " +
      data.days_left +
      " day" +
      (data.days_left === 1 ? "" : "s") +
      " remaining";
    btn.textContent = "Activate License";
    btn.hidden = false;
  } else if (state === "trial_expired") {
    banner.classList.add("ml-license-banner--expired");
    text.textContent = "Trial expired \u2014 activate a license to continue.";
    btn.textContent = "Activate Now";
    btn.hidden = false;
  } else if (state === "education") {
    banner.classList.add("ml-license-banner--education");
    text.textContent =
      "Education License" +
      (data.expiry_date ? " \u2014 expires " + data.expiry_date : "");
    btn.hidden = true;
  } else if (state === "education_expired") {
    banner.classList.add("ml-license-banner--expired");
    text.textContent = "Education license expired.";
    btn.textContent = "Activate License";
    btn.hidden = false;
  } else if (state === "subscription_lapsed") {
    banner.classList.add("ml-license-banner--expired");
    text.textContent = "Subscription lapsed \u2014 please renew to continue.";
    btn.textContent = "Activate License";
    btn.hidden = false;
  } else {
    banner.hidden = true;
    return;
  }

  banner.hidden = false;
  if (btn && !btn.hidden) {
    btn.onclick = function () {
      if (typeof sketchup !== "undefined") sketchup.open_about_dialog();
    };
  }

  // Disable export when the license has lapsed / expired.
  var expired =
    state === "trial_expired" ||
    state === "education_expired" ||
    state === "subscription_lapsed";
  var exportBtn = document.getElementById("exportBtn");
  if (exportBtn) {
    exportBtn.disabled = expired;
    exportBtn.title = expired
      ? "Export is disabled — activate a license to continue."
      : "";
  }
};
