"use client";

import { X } from "lucide-react";
import type { ReactNode } from "react";

type ModalProps = {
  open: boolean;
  title: string;
  description?: string;
  children: ReactNode;
  onClose: () => void;
};

export function Modal({ open, title, description, children, onClose }: ModalProps) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center px-4 py-6">
      <button className="absolute inset-0 bg-ink/35" onClick={onClose} type="button" aria-label="Close modal" />
      <section className="relative max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-lg border border-line bg-card p-5 shadow-soft">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-lg font-semibold text-ink">{title}</h2>
            {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
          </div>
          <button className="rounded-md p-2 text-muted hover:bg-surface hover:text-ink" onClick={onClose} type="button">
            <X className="h-5 w-5" aria-hidden />
          </button>
        </div>
        <div className="mt-5">{children}</div>
      </section>
    </div>
  );
}
