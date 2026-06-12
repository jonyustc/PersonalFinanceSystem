import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../dashboard/dashboard_page.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({
    super.key,
    this.initialType = 'expense',
    this.selectedCategoryId,
    this.pickerMode = false,
  });

  final String initialType;
  final String? selectedCategoryId;
  final bool pickerMode;

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  late String _type;
  String? _selectedParentId;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final categories = snapshot.categories
        .where((row) => row['type'] == _type)
        .toList();
    final parents = categories
        .where((row) => row['parent_id'] == null)
        .toList();
    _resolveInitialParent(categories);
    final selectedParent = _resolveSelectedParent(parents);
    final children = selectedParent == null
        ? <Map<String, dynamic>>[]
        : categories
              .where((row) => row['parent_id'] == selectedParent['id'])
              .toList();
    final currency = snapshot.session?.currency ?? 'BDT';
    // Show this month's spending per category outside picker mode.
    final spend = widget.pickerMode
        ? const <String, double>{}
        : _spendingByCategory(snapshot.transactions, _type, categories);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Categories'),
                  Text(
                    'Tap to open · long-press to edit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Toggle type',
                  onPressed: () {
                    setState(() {
                      _type = _type == 'expense' ? 'income' : 'expense';
                      _selectedParentId = null;
                    });
                  },
                  icon: Icon(
                    _type == 'expense' ? Icons.north_east : Icons.south_west,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'add_parent') _showCategoryEditor();
                    if (value == 'add_child' && selectedParent != null) {
                      _showCategoryEditor(parent: selectedParent);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'add_parent',
                      child: Text('Add category'),
                    ),
                    PopupMenuItem(
                      value: 'add_child',
                      enabled: selectedParent != null,
                      child: const Text('Add subcategory'),
                    ),
                  ],
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'expense',
                      label: Text('Expense'),
                      icon: Icon(Icons.north_east),
                    ),
                    ButtonSegment(
                      value: 'income',
                      label: Text('Income'),
                      icon: Icon(Icons.south_west),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) {
                    setState(() {
                      _type = value.first;
                      _selectedParentId = null;
                    });
                  },
                ),
              ),
            ),
            if (parents.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: EmptyPanel(
                    icon: Icons.category_outlined,
                    title: 'No categories yet',
                    body: 'Use the menu to add your first category.',
                  ),
                ),
              )
            else
              SliverFillRemaining(
                hasScrollBody: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 11,
                      child: _ParentCategoryList(
                        rows: parents,
                        selectedId: selectedParent?['id'] as String?,
                        spend: spend,
                        currency: currency,
                        onSelected: (id) =>
                            setState(() => _selectedParentId = id),
                        onLongPress: (row) => _showCategoryActions(row),
                        onAdd: () => _showCategoryEditor(),
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: _ChildCategoryList(
                        parent: selectedParent,
                        rows: children,
                        selectedId: widget.selectedCategoryId,
                        spend: spend,
                        currency: currency,
                        onSelected: widget.pickerMode ? _pickCategory : null,
                        onLongPress: (row) => _showCategoryActions(row),
                        onAdd: selectedParent == null
                            ? null
                            : () => _showCategoryEditor(parent: selectedParent),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add category',
        onPressed: () => _showCategoryEditor(parent: selectedParent),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// This month's posted spend per category for [type]. Parent totals roll up
  /// their own direct spend plus all children, mirroring the backend's
  /// child_spent + direct_spent rollup (`budget.py` / `report.py`).
  Map<String, double> _spendingByCategory(
    List<Map<String, dynamic>> transactions,
    String type,
    List<Map<String, dynamic>> typeCategories,
  ) {
    final now = DateTime.now();
    final direct = <String, double>{};
    for (final row in transactions) {
      if ((row['type'] as String? ?? '') != type) continue;
      if ((row['transaction_status'] as String? ?? 'posted') != 'posted') {
        continue;
      }
      final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
      if (date == null) continue;
      final local = date.toLocal();
      if (local.year != now.year || local.month != now.month) continue;
      final categoryId = row['category_id'] as String?;
      if (categoryId == null) continue;
      direct[categoryId] = (direct[categoryId] ?? 0) + asDouble(row['amount']);
    }

    final childrenByParent = <String, List<String>>{};
    for (final category in typeCategories) {
      final parentId = category['parent_id'] as String?;
      if (parentId != null) {
        childrenByParent
            .putIfAbsent(parentId, () => [])
            .add(category['id'] as String);
      }
    }

    final totals = <String, double>{};
    for (final category in typeCategories) {
      final id = category['id'] as String;
      if (category['parent_id'] != null) {
        totals[id] = direct[id] ?? 0;
        continue;
      }
      var total = direct[id] ?? 0;
      for (final childId in childrenByParent[id] ?? const <String>[]) {
        total += direct[childId] ?? 0;
      }
      totals[id] = total;
    }
    return totals;
  }

  void _resolveInitialParent(List<Map<String, dynamic>> categories) {
    if (_selectedParentId != null || widget.selectedCategoryId == null) return;
    for (final row in categories) {
      if (row['id'] == widget.selectedCategoryId) {
        _selectedParentId = row['parent_id'] as String? ?? row['id'] as String?;
        return;
      }
    }
  }

  Map<String, dynamic>? _resolveSelectedParent(
    List<Map<String, dynamic>> parents,
  ) {
    if (parents.isEmpty) return null;
    for (final row in parents) {
      if (row['id'] == _selectedParentId) return row;
    }
    _selectedParentId = parents.first['id'] as String;
    return parents.first;
  }

  void _pickCategory(Map<String, dynamic> category) {
    Navigator.of(context).pop(category);
  }

  Future<void> _showCategoryEditor({
    Map<String, dynamic>? category,
    Map<String, dynamic>? parent,
  }) async {
    final result = await showDialog<_CategoryEditResult>(
      context: context,
      builder: (_) => _CategoryEditorDialog(
        type: _type,
        category: category,
        parent: parent,
      ),
    );
    if (result == null) return;
    try {
      if (category == null) {
        final created = await ref
            .read(appControllerProvider.notifier)
            .createCategory(
              name: result.name,
              type: result.type,
              parentId: result.parentId,
              color: result.color,
              icon: result.icon,
            );
        if (result.parentId == null) {
          setState(() => _selectedParentId = created['id']?.toString());
        }
      } else {
        await ref
            .read(appControllerProvider.notifier)
            .updateCategory(
              id: category['id'] as String,
              name: result.name,
              type: result.type,
              parentId: result.parentId,
              color: result.color,
              icon: result.icon,
            );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showCategoryActions(Map<String, dynamic> category) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modify'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _showCategoryEditor(category: category);
    }
    if (action == 'delete') {
      await _confirmDelete(category);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> category) async {
    final name = category['name'] as String? ?? 'Category';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete $name? Existing transactions may block this action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .deleteCategory(category['id'] as String);
      if (_selectedParentId == category['id']) {
        setState(() => _selectedParentId = null);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _ParentCategoryList extends StatelessWidget {
  const _ParentCategoryList({
    required this.rows,
    required this.selectedId,
    required this.spend,
    required this.currency,
    required this.onSelected,
    required this.onLongPress,
    required this.onAdd,
  });

  final List<Map<String, dynamic>> rows;
  final String? selectedId;
  final Map<String, double> spend;
  final String currency;
  final ValueChanged<String> onSelected;
  final ValueChanged<Map<String, dynamic>> onLongPress;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: rows.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          if (index == rows.length) {
            return _CategoryRow(
              title: 'Add category',
              icon: Icons.add,
              selected: false,
              muted: true,
              onTap: onAdd,
            );
          }
          final row = rows[index];
          final id = row['id'] as String;
          return _CategoryRow(
            title: row['name'] as String? ?? 'Category',
            icon: _iconFor(row),
            selected: id == selectedId,
            amount: spend[id],
            currency: currency,
            trailingChevron: true,
            onTap: () => onSelected(id),
            onLongPress: () => onLongPress(row),
          );
        },
      ),
    );
  }
}

class _ChildCategoryList extends StatelessWidget {
  const _ChildCategoryList({
    required this.parent,
    required this.rows,
    required this.selectedId,
    required this.spend,
    required this.currency,
    required this.onSelected,
    required this.onLongPress,
    required this.onAdd,
  });

  final Map<String, dynamic>? parent;
  final List<Map<String, dynamic>> rows;
  final String? selectedId;
  final Map<String, double> spend;
  final String currency;
  final ValueChanged<Map<String, dynamic>>? onSelected;
  final ValueChanged<Map<String, dynamic>> onLongPress;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF0F1620) : const Color(0xFFF1F4F9),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: rows.length + (onSelected == null ? 1 : 2),
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          if (onSelected != null && index == 0 && parent != null) {
            return _CategoryRow(
              title: parent!['name'] as String? ?? 'Category',
              subtitle: 'Use parent category',
              icon: _iconFor(parent!),
              selected: parent!['id'] == selectedId,
              currency: currency,
              onTap: () => onSelected!(parent!),
            );
          }
          final rowIndex = onSelected == null ? index : index - 1;
          if (rowIndex == rows.length) {
            return _CategoryRow(
              title: 'Add subcategory',
              icon: Icons.add,
              selected: false,
              muted: true,
              onTap: onAdd ?? () {},
            );
          }
          final row = rows[rowIndex];
          final id = row['id'] as String;
          return _CategoryRow(
            title: row['name'] as String? ?? 'Subcategory',
            icon: _iconFor(row),
            selected: id == selectedId,
            amount: spend[id],
            currency: currency,
            onTap: onSelected == null ? () {} : () => onSelected!(row),
            onLongPress: () => onLongPress(row),
          );
        },
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.amount,
    this.currency = 'BDT',
    this.onLongPress,
    this.muted = false,
    this.trailingChevron = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final double? amount;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool muted;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = scheme.primary;
    final hasAmount = amount != null && amount! > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: muted
                      ? scheme.onSurfaceVariant
                      : selected
                      ? primary
                      : scheme.onSurface,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted
                              ? scheme.onSurfaceVariant
                              : selected
                              ? primary
                              : null,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (hasAmount)
                        Text(
                          money(amount!, currency: currency),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailingChevron)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({required this.type, this.category, this.parent});

  final String type;
  final Map<String, dynamic>? category;
  final Map<String, dynamic>? parent;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _icon;
  late String _color;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.category?['name'] as String? ?? '',
    );
    _icon = widget.category?['icon'] as String? ?? 'category';
    _color = widget.category?['color'] as String? ?? '#0F766E';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.category != null;
    final parentName = widget.parent?['name'] as String?;
    final isChild =
        widget.parent != null ||
        (widget.category?['parent_id'] as String?) != null;
    return AlertDialog(
      title: Text(isEdit ? 'Modify category' : 'Add category'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (parentName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Under $parentName'),
                ),
              ),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _icon,
              decoration: const InputDecoration(
                labelText: 'Icon',
                prefixIcon: Icon(Icons.image_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'category', child: Text('Category')),
                DropdownMenuItem(value: 'phone', child: Text('Phone')),
                DropdownMenuItem(value: 'money', child: Text('Money')),
                DropdownMenuItem(value: 'health', child: Text('Health')),
                DropdownMenuItem(value: 'home', child: Text('Home')),
                DropdownMenuItem(value: 'shopping', child: Text('Shopping')),
              ],
              onChanged: (value) => setState(() => _icon = value ?? _icon),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _color,
              decoration: const InputDecoration(
                labelText: 'Color',
                prefixIcon: Icon(Icons.palette_outlined),
              ),
              items: const [
                DropdownMenuItem(value: '#0F766E', child: Text('Teal')),
                DropdownMenuItem(value: '#16A34A', child: Text('Green')),
                DropdownMenuItem(value: '#2563EB', child: Text('Blue')),
                DropdownMenuItem(value: '#DC2626', child: Text('Red')),
                DropdownMenuItem(value: '#F59E0B', child: Text('Amber')),
              ],
              onChanged: (value) => setState(() => _color = value ?? _color),
            ),
            if (isChild)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Subcategories cannot have children.'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _CategoryEditResult(
        name: _name.text.trim(),
        type: widget.type,
        parentId:
            widget.parent?['id'] as String? ??
            widget.category?['parent_id'] as String?,
        color: _color,
        icon: _icon,
      ),
    );
  }
}

class _CategoryEditResult {
  const _CategoryEditResult({
    required this.name,
    required this.type,
    required this.parentId,
    required this.color,
    required this.icon,
  });

  final String name;
  final String type;
  final String? parentId;
  final String color;
  final String icon;
}

IconData _iconFor(Map<String, dynamic> row) {
  return switch (row['icon'] as String?) {
    'phone' => Icons.phone_android,
    'money' => Icons.attach_money,
    'health' => Icons.local_hospital_outlined,
    'home' => Icons.home_outlined,
    'shopping' => Icons.shopping_bag_outlined,
    _ => Icons.category_outlined,
  };
}
