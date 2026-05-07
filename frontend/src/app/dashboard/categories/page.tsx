"use client";

import {
  ChevronDown,
  ChevronRight,
  Edit3,
  Plus,
  RefreshCw,
  Tags,
  Trash2,
} from "lucide-react";

import { useCallback, useEffect, useMemo, useState } from "react";

import { CategoryForm } from "@/components/categories/category-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";

import {
  createCategory,
  deleteCategory,
  fetchCategorySpending,
  fetchCategoryTree,
  updateCategory,
} from "@/services/finance-service";

import { InsightsPanel } from "@/components/insights/insights-panel";
import { CategoryPie } from "@/components/reports/category-pie";
import { generateInsights } from "@/lib/insights";

import { formatCurrency } from "@/lib/utils";

import type { Category } from "@/types/api";

export default function CategoriesPage() {
  const [categories, setCategories] = useState<Category[]>([]);
  const [spending, setSpending] = useState<any[]>([]);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});

  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);

  const [error, setError] = useState<string | null>(null);

  /* ================= LOAD ================= */

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const [cats, spend] = await Promise.all([
        fetchCategoryTree(),
        fetchCategorySpending(),
      ]);

      setCategories(cats || []);
      setSpending(spend || []);
    } catch {
      setError("Failed to load");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  /* ================= FLATTEN ================= */

  const flatCategories = useMemo(() => {
    const result: Category[] = [];

    function walk(list: Category[]) {
      list.forEach((c) => {
        result.push(c);
        if (c.children) walk(c.children);
      });
    }

    walk(categories);
    return result;
  }, [categories]);

  function getName(id: string) {
    return flatCategories.find((c) => c.id === id)?.name || "Unknown";
  }

  /* ================= CHART ================= */

  const pieData = spending.map((c) => {
    const label =
      typeof c.label === "string" && c.label
        ? c.label
        : getName(String(c.id || ""));
    return {
      label,
      value: Number(c.amount),
    };
  });

  const total = pieData.reduce((s, c) => s + c.value, 0);

  const insights = generateInsights({ categories: pieData });

  /* ================= ACTION ================= */

  function toggle(id: string) {
    setExpanded((prev) => ({
      ...prev,
      [id]: !prev[id],
    }));
  }

  function openCreate() {
    setEditingCategory(null);
    setModalOpen(true);
  }

  function openEdit(cat: Category) {
    setEditingCategory(cat);
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingCategory(null);
  }

  async function handleSave(payload: any) {
    try {
      if (editingCategory) {
        await updateCategory(editingCategory.id, payload);
      } else {
        await createCategory(payload);
      }

      closeModal();
      await load();
    } catch {
      setError("Save failed");
    }
  }

  async function handleDelete(cat: Category) {
    if (!confirm(`Delete ${cat.name}?`)) return;

    try {
      await deleteCategory(cat.id);
      await load();
    } catch {
      setError("Delete failed");
    }
  }

  /* ================= TREE ================= */

  function renderNode(cat: Category, level = 0) {
    const isOpen = expanded[cat.id];

    return (
      <div key={cat.id}>
        <div
          className="flex justify-between items-center bg-white border rounded p-3 mb-2"
          style={{ marginLeft: level * 20 }}
        >
          <div className="flex items-center gap-3">
            {/* TOGGLE */}
            {cat.children?.length ? (
              <button onClick={() => toggle(cat.id)}>
                {isOpen ? (
                  <ChevronDown size={16} />
                ) : (
                  <ChevronRight size={16} />
                )}
              </button>
            ) : (
              <div className="w-4" />
            )}

            {/* ICON */}
            <span
              className="h-8 w-8 flex items-center justify-center rounded text-white"
              style={{ backgroundColor: cat.color || "#1f9d7a" }}
            >
              <Tags size={14} />
            </span>

            {/* NAME */}
            <div>
              <p className="font-medium">{cat.name}</p>
              <p className="text-xs text-gray-500">{cat.type}</p>
            </div>
          </div>

          {/* ACTION */}
          <div className="flex gap-2">
            <button onClick={() => openEdit(cat)}>
              <Edit3 size={16} />
            </button>

            <button onClick={() => handleDelete(cat)}>
              <Trash2 size={16} className="text-red-500" />
            </button>
          </div>
        </div>

        {/* CHILDREN */}
        {isOpen && cat.children?.map((c) => renderNode(c, level + 1))}
      </div>
    );
  }

  /* ================= UI ================= */

  return (
    <div className="space-y-6">
      {/* HEADER */}
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold">Categories</h1>

        <div className="flex gap-2">
          <Button onClick={load}>
            <RefreshCw size={16} />
          </Button>

          <Button onClick={openCreate}>
            <Plus size={16} />
            Add
          </Button>
        </div>
      </div>

      {error && <p className="text-red-500">{error}</p>}

      {/* SUMMARY */}
      <div className="grid md:grid-cols-2 gap-4">
        <Card title="Total Spending">
          <p className="text-2xl font-semibold">{formatCurrency(total)}</p>
        </Card>

        <Card title="Top Category">
          <p className="font-medium">{pieData[0]?.label || "--"}</p>
        </Card>
      </div>

      {/* INSIGHT */}
      <InsightsPanel items={insights} />

      {/* CHART */}
      <CategoryPie data={pieData} />

      {/* TREE */}
      <div>
        {loading && <p>Loading...</p>}

        {!loading && categories.length === 0 && <p>No categories</p>}

        {categories.map((c) => renderNode(c))}
      </div>

      {/* MODAL */}
      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editingCategory ? "Edit Category" : "Add Category"}
      >
        <CategoryForm
          category={editingCategory}
          categories={flatCategories}
          onSubmit={handleSave}
          onCancel={closeModal}
        />
      </Modal>
    </div>
  );
}

/* ================= CARD ================= */

function Card({ title, children }: any) {
  return (
    <div className="bg-white p-4 rounded-xl border shadow-sm">
      <h2 className="font-semibold mb-2">{title}</h2>
      {children}
    </div>
  );
}
