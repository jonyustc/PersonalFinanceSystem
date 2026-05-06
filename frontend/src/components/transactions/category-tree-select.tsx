"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createCategory } from "@/services/finance-service";
import { Input } from "@/components/ui/input";

export function CategoryTreeSelect({
  categories,
  type,
  value,
  onChange,
  onCreated, // 🔥 new: parent কে notify করবে
}: any) {
  const [open, setOpen] = useState(false);
  const [hoverParent, setHoverParent] = useState<any>(null);
  const [newParent, setNewParent] = useState("");
  const [newChild, setNewChild] = useState("");

  const ref = useRef<HTMLDivElement>(null);

  /* ===== CLOSE ON OUTSIDE CLICK ===== */
  useEffect(() => {
    function handleClick(e: any) {
      if (!ref.current?.contains(e.target)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  /* ===== GROUP ===== */
  const parents = useMemo(
    () => categories.filter((c: any) => !c.parent_id && c.type === type),
    [categories, type],
  );

  const childrenMap = useMemo(() => {
    const map: any = {};
    categories.forEach((c: any) => {
      if (c.parent_id) {
        if (!map[c.parent_id]) map[c.parent_id] = [];
        map[c.parent_id].push(c);
      }
    });
    return map;
  }, [categories]);

  const selected = categories.find((c: any) => c.id === value);

  /* ===== ADD ===== */
  async function addParent() {
    if (!newParent.trim()) return;

    const cat = await createCategory({
      name: newParent,
      type,
      parent_id: null,
    });

    onCreated(cat); // 🔥 update list in parent
    onChange(cat.id); // 🔥 auto select

    setNewParent("");
    setOpen(false);
  }

  async function addChild() {
    if (!newChild.trim() || !hoverParent) return;

    const cat = await createCategory({
      name: newChild,
      type,
      parent_id: hoverParent.id,
    });

    onCreated(cat);
    onChange(cat.id);

    setNewChild("");
    setOpen(false);
  }

  return (
    <div ref={ref} className="relative">
      {/* SELECT BOX */}
      <div
        onClick={() => setOpen(!open)}
        className="input cursor-pointer flex justify-between"
      >
        <span>{selected?.name || "Select category"}</span>
        <span>▾</span>
      </div>

      {open && (
        <div className="absolute z-50 mt-1 bg-white border rounded-xl shadow-lg flex w-full min-h-[250px]">
          {/* LEFT (PARENT) */}
          <div className="w-1/2 border-r overflow-y-auto max-h-64">
            {parents.map((p: any) => (
              <div
                key={p.id}
                onMouseEnter={() => setHoverParent(p)}
                className={`px-3 py-2 cursor-pointer ${
                  hoverParent?.id === p.id ? "bg-gray-100" : ""
                }`}
              >
                {p.name}
              </div>
            ))}

            <div className="p-2 border-t space-y-1">
              <Input
                placeholder="Add parent..."
                value={newParent}
                onChange={(e) => setNewParent(e.target.value)}
              />
              <button onClick={addParent} className="text-blue-600 text-sm">
                + Add parent
              </button>
            </div>
          </div>

          {/* RIGHT (CHILD) */}
          <div className="w-1/2 overflow-y-auto max-h-64">
            {hoverParent ? (
              <>
                {(childrenMap[hoverParent.id] || []).map((c: any) => (
                  <div
                    key={c.id}
                    onClick={() => {
                      onChange(c.id);
                      setOpen(false);
                    }}
                    className={`px-3 py-2 cursor-pointer ${
                      value === c.id ? "bg-blue-100" : ""
                    }`}
                  >
                    {c.name}
                  </div>
                ))}

                <div className="p-2 border-t space-y-1">
                  <Input
                    placeholder="Add sub-category..."
                    value={newChild}
                    onChange={(e) => setNewChild(e.target.value)}
                  />
                  <button onClick={addChild} className="text-green-600 text-sm">
                    + Add child
                  </button>
                </div>
              </>
            ) : (
              <div className="p-4 text-sm text-gray-400">Hover a category</div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
