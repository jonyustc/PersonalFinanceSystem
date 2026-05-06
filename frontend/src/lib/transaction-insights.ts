export function generateTransactionInsights(data: any[]) {
  if (!data?.length) return [];

  const insights = [];

  const total = data.reduce((s, d) => s + d.amount, 0);
  const avg = total / data.length;

  const max = data.reduce((m, d) => (d.amount > m.amount ? d : m));

  if (max.amount > avg * 2) {
    insights.push({
      type: "warning",
      title: "Spending Spike",
      message: `You spent unusually high on ${max.date}`,
    });
  }

  insights.push({
    type: "info",
    title: "Average Spending",
    message: `Your daily average is ${avg.toFixed(2)}`,
  });

  return insights;
}
