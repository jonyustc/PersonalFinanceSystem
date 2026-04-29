"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Save } from "lucide-react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { Category, CategoryCreatePayload, CategoryUpdatePayload } from "@/types/api";

const schema = z.object({
  name: z.string().min(1, "Category name is required").max(120),
  type: z.enum(["expense", "income"]),
  color: z.string().max(20).optional(),
  icon: z.string().max(80).optional()
});

type FormValues = z.infer<typeof schema>;

type CategoryFormProps = {
  category?: Category | null;
  onSubmit: (payload: CategoryCreatePayload | CategoryUpdatePayload) => Promise<void>;
  onCancel: () => void;
};

export function CategoryForm({ category, onSubmit, onCancel }: CategoryFormProps) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting }
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: category?.name ?? "",
      type: category?.type ?? "expense",
      color: category?.color ?? "#1f9d7a",
      icon: category?.icon ?? ""
    }
  });

  async function submit(values: FormValues) {
    await onSubmit({
      name: values.name.trim(),
      type: values.type,
      color: values.color?.trim() || null,
      icon: values.icon?.trim() || null
    });
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit(submit)}>
      <Input label="Category name" error={errors.name?.message} {...register("name")} />

      <div className="grid grid-cols-2 gap-2 rounded-md bg-surface p-1">
        <label className="cursor-pointer">
          <input className="peer sr-only" type="radio" value="expense" {...register("type")} />
          <span className="block rounded-md px-3 py-2 text-center text-sm font-semibold text-muted peer-checked:bg-white peer-checked:text-ink peer-checked:shadow-sm">
            Expense
          </span>
        </label>
        <label className="cursor-pointer">
          <input className="peer sr-only" type="radio" value="income" {...register("type")} />
          <span className="block rounded-md px-3 py-2 text-center text-sm font-semibold text-muted peer-checked:bg-white peer-checked:text-ink peer-checked:shadow-sm">
            Income
          </span>
        </label>
      </div>

      <div className="grid gap-4 sm:grid-cols-[120px_1fr]">
        <label className="block">
          <span className="mb-2 block text-sm font-medium text-ink">Color</span>
          <input
            className="h-11 w-full rounded-md border border-line bg-white px-2 outline-none transition focus:border-brand-600 focus:ring-4 focus:ring-brand-100"
            type="color"
            {...register("color")}
          />
        </label>
        <Input label="Icon" placeholder="shopping-bag, salary, food" error={errors.icon?.message} {...register("icon")} />
      </div>

      <div className="flex justify-end gap-3 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={isSubmitting}>
          <Save className="h-4 w-4" aria-hidden />
          {isSubmitting ? "Saving..." : "Save category"}
        </Button>
      </div>
    </form>
  );
}
