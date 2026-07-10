"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useMemo, useState } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

import type {
  Category,
  CategoryCreatePayload,
  CategoryUpdatePayload,
} from "@/types/api";

/* ================= SCHEMA ================= */

const schema = z.object({
  name: z.string().min(1, "Name required"),
  type: z.enum(["expense", "income"]),
  parent_id: z.string().optional(),
  color: z.string().optional(),
  icon: z.string().optional(),
});

type FormData = z.infer<typeof schema>;

type Props = {
  category?: Category | null;
  categories?: Category[];
  onSubmit: (
    data: CategoryCreatePayload | CategoryUpdatePayload,
  ) => Promise<void>;
  onCancel: () => void;
};

export function CategoryForm({
  category,
  categories = [],
  onSubmit,
  onCancel,
}: Props) {
  const [open, setOpen] = useState(false);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { isSubmitting },
  } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: category?.name || "",
      type: category?.type || "expense",
      parent_id: category?.parent_id || "",
      color: category?.color || "#1f9d7a",
      icon: category?.icon || "",
    },
  });

  const type = watch("type");
  const selectedParent = watch("parent_id");

  /* ===== ONLY PARENTS ===== */

  const parents = useMemo(
    () =>
      categories.filter(
        (c) =>
          !c.parent_id &&
          c.type === type &&
          (!category || c.id !== category.id),
      ),
    [categories, type, category],
  );

  const selectedName =
    parents.find((c) => c.id === selectedParent)?.name || "No Parent";

  /* ===== SUBMIT ===== */

  async function submit(data: FormData) {
    await onSubmit({
      name: data.name.trim(),
      type: data.type,
      parent_id: data.parent_id || null,
      color: data.color || null,
      icon: data.icon || null,
    });
  }

  return (
    <form onSubmit={handleSubmit(submit)} className="space-y-5">
      {/* NAME */}
      <Input placeholder="Category name" {...register("name")} />

      {/* TYPE */}
      <select {...register("type")} className="input">
        <option value="expense">Expense</option>
        <option value="income">Income</option>
      </select>

      {/* ===== SIMPLE PARENT SELECT ===== */}
      <div className="relative">
        <label className="text-sm font-medium">Parent Category</label>

        <div
          onClick={() => setOpen(!open)}
          className="input cursor-pointer flex justify-between mt-1"
        >
          <span>{selectedName}</span>
          <span>▾</span>
        </div>

        {open && (
          <div className="absolute z-50 mt-1 bg-card border rounded-xl shadow-lg w-full max-h-64 overflow-y-auto">
            {/* NO PARENT */}
            <div
              onClick={() => {
                setValue("parent_id", "", {
                  shouldValidate: true,
                  shouldDirty: true,
                });
                setOpen(false);
              }}
              className="px-3 py-2 hover:bg-surface cursor-pointer"
            >
              No Parent
            </div>

            {/* PARENTS ONLY */}
            {parents.map((p) => (
              <div
                key={p.id}
                onClick={() => {
                  setValue("parent_id", p.id, {
                    shouldValidate: true,
                    shouldDirty: true,
                  });
                  setOpen(false);
                }}
                className={`px-3 py-2 cursor-pointer hover:bg-brand-600/10 ${
                  selectedParent === p.id ? "bg-brand-600/15 text-brand-700" : ""
                }`}
              >
                {p.name}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* COLOR */}
      <input type="color" {...register("color")} />

      {/* ICON */}
      <Input placeholder="Icon (optional)" {...register("icon")} />

      {/* ACTION */}
      <div className="flex justify-end gap-2">
        <Button type="button" onClick={onCancel}>
          Cancel
        </Button>

        <Button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Saving..." : "Save"}
        </Button>
      </div>
    </form>
  );
}
