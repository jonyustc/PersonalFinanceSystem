"use client";

import { Plus } from "lucide-react";
import { useMemo, useState } from "react";

import { createCategory } from "@/services/finance-service";

export function CategoryTreeSelect({
  categories,
  type,
  value,
  onChange,
  onCreated,
}: any) {
  const [newCategoryName, setNewCategoryName] = useState("");
  const [newSubcategoryName, setNewSubcategoryName] = useState("");
  const [addMode, setAddMode] = useState<"category" | "subcategory" | null>(null);
  const [saving, setSaving] = useState<"category" | "subcategory" | null>(null);

  const parents = useMemo(
    () => categories.filter((category: any) => !category.parent_id && category.type === type),
    [categories, type],
  );

  const selected = categories.find((category: any) => category.id === value);
  const selectedParentId = selected?.parent_id ?? selected?.id ?? "";
  const children = useMemo(
    () => categories.filter((category: any) => category.parent_id === selectedParentId),
    [categories, selectedParentId],
  );

  async function addCategory() {
    const name = newCategoryName.trim();
    if (!name) return;
    setSaving("category");
    try {
      const category = await createCategory({ name, type, parent_id: null });
      onCreated?.(category);
      onChange(category.id);
      setNewCategoryName("");
      setAddMode(null);
    } finally {
      setSaving(null);
    }
  }

  async function addSubcategory() {
    const name = newSubcategoryName.trim();
    if (!name || !selectedParentId) return;
    setSaving("subcategory");
    try {
      const category = await createCategory({ name, type, parent_id: selectedParentId });
      onCreated?.(category);
      onChange(category.id);
      setNewSubcategoryName("");
      setAddMode(null);
    } finally {
      setSaving(null);
    }
  }

  return (
    <div className="grid gap-2">
      <div className="grid gap-2 sm:grid-cols-2">
        <label className="block">
          <span className="mb-1.5 flex items-center justify-between text-sm font-medium text-ink">
            Category
            <button
              type="button"
              onClick={(event) => {
                event.preventDefault();
                setAddMode((current) => (current === "category" ? null : "category"));
              }}
              className="inline-flex h-7 items-center gap-1 rounded-md border border-line bg-white px-2 text-xs font-semibold text-brand-700"
            >
              <Plus className="h-3.5 w-3.5" />
              New
            </button>
          </span>
          <select
            className="input h-10"
            value={selectedParentId}
            onChange={(event) => onChange(event.target.value)}
          >
            <option value="">Select category</option>
            {parents.map((category: any) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="mb-1.5 flex items-center justify-between text-sm font-medium text-ink">
            Subcategory
            <button
              type="button"
              disabled={!selectedParentId}
              onClick={(event) => {
                event.preventDefault();
                setAddMode((current) => (current === "subcategory" ? null : "subcategory"));
              }}
              className="inline-flex h-7 items-center gap-1 rounded-md border border-line bg-white px-2 text-xs font-semibold text-brand-700 disabled:opacity-50"
            >
              <Plus className="h-3.5 w-3.5" />
              New
            </button>
          </span>
          <select
            className="input h-10"
            disabled={!selectedParentId || children.length === 0}
            value={selected?.parent_id ? selected.id : ""}
            onChange={(event) => onChange(event.target.value || selectedParentId)}
          >
            <option value="">{children.length ? "No subcategory" : "No subcategories"}</option>
            {children.map((category: any) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      {addMode ? (
        <div className="grid gap-2 rounded-md border border-line bg-surface p-2 sm:grid-cols-[1fr_auto_auto]">
          <input
            className="input h-10 bg-white text-sm"
            placeholder={addMode === "category" ? `Add ${type} category` : "Add subcategory"}
            value={addMode === "category" ? newCategoryName : newSubcategoryName}
            onChange={(event) =>
              addMode === "category"
                ? setNewCategoryName(event.target.value)
                : setNewSubcategoryName(event.target.value)
            }
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                addMode === "category" ? addCategory() : addSubcategory();
              }
            }}
          />
          <button
            type="button"
            onClick={addMode === "category" ? addCategory : addSubcategory}
            disabled={
              addMode === "category"
                ? !newCategoryName.trim() || saving === "category"
                : !newSubcategoryName.trim() || saving === "subcategory"
            }
            className="inline-flex h-10 items-center justify-center gap-2 rounded-md border border-line bg-white px-3 text-sm font-semibold text-ink disabled:opacity-50"
          >
            <Plus className="h-4 w-4" />
            Add
          </button>
          <button
            type="button"
            onClick={() => setAddMode(null)}
            className="h-10 rounded-md border border-line bg-white px-3 text-sm font-semibold text-muted"
          >
            Cancel
          </button>
        </div>
      ) : null}
    </div>
  );
}
