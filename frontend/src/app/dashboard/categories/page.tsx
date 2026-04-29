"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Edit3, Plus, RefreshCw, Tags, Trash2 } from "lucide-react";

import { CategoryForm } from "@/components/categories/category-form";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { createCategory, deleteCategory, fetchCategories, updateCategory } from "@/services/finance-service";
import type { Category, CategoryCreatePayload, CategoryUpdatePayload } from "@/types/api";

export default function CategoriesPage() {
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const counts = useMemo(
    () => ({
      expense: categories.filter((category) => category.type === "expense").length,
      income: categories.filter((category) => category.type === "income").length
    }),
    [categories]
  );

  const loadCategories = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setCategories(await fetchCategories());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to load categories");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadCategories();
  }, [loadCategories]);

  function openCreateModal() {
    setEditingCategory(null);
    setModalOpen(true);
  }

  function openEditModal(category: Category) {
    setEditingCategory(category);
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingCategory(null);
  }

  async function handleSave(payload: CategoryCreatePayload | CategoryUpdatePayload) {
    if (editingCategory) {
      await updateCategory(editingCategory.id, payload as CategoryUpdatePayload);
    } else {
      await createCategory(payload as CategoryCreatePayload);
    }
    closeModal();
    await loadCategories();
  }

  async function handleDelete(category: Category) {
    const confirmed = window.confirm(`Delete "${category.name}"? Existing transactions may lose this category.`);
    if (!confirmed) return;

    setDeletingId(category.id);
    setError(null);
    try {
      await deleteCategory(category.id);
      await loadCategories();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to delete category");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Categories</h1>
          <p className="mt-1 text-sm text-muted">Set up income and expense categories used by transactions and budgets.</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Button variant="secondary" onClick={loadCategories} disabled={loading}>
            <RefreshCw className="h-4 w-4" aria-hidden />
            Refresh
          </Button>
          <Button onClick={openCreateModal}>
            <Plus className="h-4 w-4" aria-hidden />
            Add category
          </Button>
        </div>
      </div>

      <section className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Total categories</p>
          <p className="mt-2 text-2xl font-semibold text-ink">{categories.length}</p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Expense categories</p>
          <p className="mt-2 text-2xl font-semibold text-ink">{counts.expense}</p>
        </div>
        <div className="rounded-lg border border-line bg-white p-5 shadow-soft">
          <p className="text-sm text-muted">Income categories</p>
          <p className="mt-2 text-2xl font-semibold text-ink">{counts.income}</p>
        </div>
      </section>

      {error ? <p className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</p> : null}

      <section className="hidden overflow-hidden rounded-lg border border-line bg-white shadow-soft lg:block">
        <div className="grid grid-cols-[1fr_140px_120px_160px_120px] gap-4 border-b border-line px-5 py-3 text-xs font-semibold uppercase text-muted">
          <span>Name</span>
          <span>Type</span>
          <span>Color</span>
          <span>Icon</span>
          <span className="text-right">Actions</span>
        </div>
        {loading ? <p className="px-5 py-6 text-sm text-muted">Loading categories...</p> : null}
        {!loading && !categories.length ? <p className="px-5 py-6 text-sm text-muted">No categories yet.</p> : null}
        {categories.map((category) => (
          <div
            className="grid grid-cols-[1fr_140px_120px_160px_120px] items-center gap-4 border-b border-line px-5 py-4 text-sm last:border-0"
            key={category.id}
          >
            <div className="flex min-w-0 items-center gap-3">
              <span className="flex h-9 w-9 items-center justify-center rounded-md text-white" style={{ backgroundColor: category.color ?? "#1f9d7a" }}>
                <Tags className="h-4 w-4" aria-hidden />
              </span>
              <span className="truncate font-semibold text-ink">{category.name}</span>
            </div>
            <span className={category.type === "income" ? "font-medium text-brand-700" : "font-medium text-amber-700"}>{category.type}</span>
            <span className="text-muted">{category.color ?? "-"}</span>
            <span className="truncate text-muted">{category.icon ?? "-"}</span>
            <div className="flex justify-end gap-2">
              <button className="rounded-md p-2 text-muted hover:bg-surface hover:text-ink" onClick={() => openEditModal(category)} type="button">
                <Edit3 className="h-4 w-4" aria-hidden />
              </button>
              <button
                className="rounded-md p-2 text-muted hover:bg-red-50 hover:text-red-700 disabled:opacity-50"
                disabled={deletingId === category.id}
                onClick={() => handleDelete(category)}
                type="button"
              >
                <Trash2 className="h-4 w-4" aria-hidden />
              </button>
            </div>
          </div>
        ))}
      </section>

      <section className="grid gap-4 lg:hidden">
        {loading ? <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">Loading categories...</p> : null}
        {!loading && !categories.length ? <p className="rounded-lg border border-line bg-white p-4 text-sm text-muted">No categories yet.</p> : null}
        {categories.map((category) => (
          <article className="rounded-lg border border-line bg-white p-5 shadow-soft" key={category.id}>
            <div className="flex items-start justify-between gap-4">
              <div className="flex min-w-0 items-center gap-3">
                <span className="flex h-10 w-10 items-center justify-center rounded-md text-white" style={{ backgroundColor: category.color ?? "#1f9d7a" }}>
                  <Tags className="h-4 w-4" aria-hidden />
                </span>
                <div className="min-w-0">
                  <h2 className="truncate text-lg font-semibold text-ink">{category.name}</h2>
                  <p className="text-sm text-muted">{category.icon || category.color || "No icon"}</p>
                </div>
              </div>
              <span className={category.type === "income" ? "text-sm font-semibold text-brand-700" : "text-sm font-semibold text-amber-700"}>
                {category.type}
              </span>
            </div>
            <div className="mt-4 flex gap-2">
              <Button className="flex-1" variant="secondary" onClick={() => openEditModal(category)}>
                <Edit3 className="h-4 w-4" aria-hidden />
                Edit
              </Button>
              <Button className="flex-1" variant="secondary" disabled={deletingId === category.id} onClick={() => handleDelete(category)}>
                <Trash2 className="h-4 w-4" aria-hidden />
                Delete
              </Button>
            </div>
          </article>
        ))}
      </section>

      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editingCategory ? "Edit category" : "Add category"}
        description="Categories organize transactions and power budget reporting."
      >
        <CategoryForm category={editingCategory} onCancel={closeModal} onSubmit={handleSave} />
      </Modal>
    </div>
  );
}
