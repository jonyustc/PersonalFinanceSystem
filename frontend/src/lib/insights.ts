type CategorySpend = { label: string; value: number };
type BudgetItem = { category_id: string; amount: number; spent: number };

export type Insight = {
  type: "warning" | "info" | "success";
  title: string;
  message: string;
};

export function generateInsights(params: {
  categories: CategorySpend[]; // pieData: [{label, value}]
  budgets?: BudgetItem[]; // optional budgets
  prevCategories?: CategorySpend[]; // last month data (optional)
}) {
  const { categories, budgets = [], prevCategories = [] } = params;

  const insights: Insight[] = [];

  if (!categories?.length) return insights;

  const total = categories.reduce((s, c) => s + (c.value || 0), 0) || 1;

  // 🥇 Top category share
  const top = categories.reduce((m, c) => (c.value > m.value ? c : m));
  const topPct = Math.round((top.value / total) * 100);

  if (topPct >= 35) {
    insights.push({
      type: "warning",
      title: "High concentration",
      message: `${top.label} takes ${topPct}% of your expenses. Consider reducing it.`,
    });
  } else {
    insights.push({
      type: "info",
      title: "Balanced spending",
      message: `Top category (${top.label}) is ${topPct}% of total—looks balanced.`,
    });
  }

  // 🔴 Overspending vs budget
  if (budgets.length) {
    const overs = budgets
      .filter((b) => (b.spent || 0) > (b.amount || 0))
      .sort((a, b) => b.spent - a.spent);

    if (overs.length) {
      const worst = overs[0];
      const diff = worst.spent - worst.amount;
      insights.push({
        type: "warning",
        title: "Overspending detected",
        message: `You exceeded a budget by ${diff.toFixed(
          2,
        )}. Review this category.`,
      });
    } else {
      insights.push({
        type: "success",
        title: "Within budget",
        message: "All tracked categories are within budget. Good job!",
      });
    }
  }

  // ⚠️ Spike vs previous month
  if (prevCategories.length) {
    const prevMap = new Map(prevCategories.map((p) => [p.label, p.value]));
    let biggestSpike: { label: string; pct: number } | null = null;

    for (const c of categories) {
      const prev = prevMap.get(c.label) || 0;
      if (prev <= 0) continue;
      const pct = ((c.value - prev) / prev) * 100;
      if (pct > 30) {
        if (!biggestSpike || pct > biggestSpike.pct) {
          biggestSpike = { label: c.label, pct };
        }
      }
    }

    if (biggestSpike) {
      insights.push({
        type: "warning",
        title: "Spending spike",
        message: `${biggestSpike.label} increased by ${Math.round(
          biggestSpike.pct,
        )}% vs last month.`,
      });
    }
  }

  // 🧭 Simple saving tip
  if (topPct >= 35) {
    insights.push({
      type: "info",
      title: "Tip",
      message: `Try a 10% cut in ${top.label} next month to improve savings.`,
    });
  }

  return insights;
}
