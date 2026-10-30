import 'package:flutter/material.dart';

import 'api.dart';

class Pal {
  static const ink = Color(0xFF1C2340);
  static const brand = Color(0xFF2F3E9E);
  static const bg = Color(0xFFF4F6FB);
  static const line = Color(0xFFDFE3EF);
  static const muted = Color(0xFF6A7290);
  static const ok = Color(0xFF1B8A4A);
  static const warn = Color(0xFFC77A00);
  static const bad = Color(0xFFC62828);
}

ThemeData adminTheme() => ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(seedColor: Pal.brand, surface: Colors.white),
      scaffoldBackgroundColor: Pal.bg,
      dividerColor: Pal.line,
      visualDensity: VisualDensity.compact,
      dataTableTheme: const DataTableThemeData(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 52,
        headingTextStyle: TextStyle(
            fontWeight: FontWeight.w700, color: Pal.ink, fontSize: 13),
        dataTextStyle: TextStyle(color: Pal.ink, fontSize: 13),
      ),
    );

String fmtTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(
      iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z');
  if (d == null) return iso;
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String errorText(Object e) {
  if (e is AdminApiException) {
    if (e.isNetwork) {
      return 'Cannot reach the server. Check the address and your connection.';
    }
    return switch (e.code) {
      'invalid_credentials' => 'Wrong username, password or code.',
      'locked' => 'Too many tries. Locked for 15 minutes.',
      _ => 'The server answered "${e.code}" (${e.status}).',
    };
  }
  return '$e';
}

class Chip2 extends StatelessWidget {
  const Chip2(this.text, {super.key, this.color = Pal.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}

class Panel extends StatelessWidget {
  const Panel({super.key, this.title, required this.child, this.actions});
  final String? title;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Pal.line)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(
                      child: Text(title!,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Pal.ink))),
                  ...?actions,
                ]),
              ),
            child,
          ]),
        ),
      );
}

class StatCard extends StatelessWidget {
  const StatCard(this.label, this.value,
      {super.key, this.color = Pal.brand, this.hint});
  final String label, value;
  final String? hint;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Pal.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Pal.ink, fontWeight: FontWeight.w600)),
          if (hint != null)
            Text(hint!,
                style: const TextStyle(fontSize: 11.5, color: Pal.muted)),
        ]),
      );
}

/// A page-sized table that loads one page at a time and has a search box. Rows are
/// only ever read; tapping one opens its detail.
class PagedTable extends StatefulWidget {
  const PagedTable({
    super.key,
    required this.fetch,
    required this.columns,
    required this.cells,
    this.onRow,
    this.searchHint = 'Search',
    this.filters = const [],
    this.pageSize = 25,
    this.reloadKey = '',
  });
  final Future<Map<String, dynamic>> Function(int offset, int limit, String q)
      fetch;
  final List<String> columns;
  final List<DataCell> Function(Map<String, dynamic> row) cells;
  final void Function(Map<String, dynamic> row)? onRow;
  final String searchHint;
  final List<Widget> filters;
  final int pageSize;

  /// Change it to make the table load again (a filter changed).
  final String reloadKey;

  @override
  State<PagedTable> createState() => _PagedTableState();
}

class _PagedTableState extends State<PagedTable> {
  List<Map<String, dynamic>> _rows = [];
  int _total = 0, _offset = 0;
  String _q = '';
  Object? _error;
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PagedTable old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) {
      _offset = 0;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final j = await widget.fetch(_offset, widget.pageSize, _q);
      if (!mounted) return;
      setState(() {
        _rows = (j['items'] as List).cast<Map<String, dynamic>>();
        _total = j['total'] as int;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = (_offset + widget.pageSize).clamp(0, _total);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
              fillColor: Colors.white,
              filled: true,
            ),
            onSubmitted: (v) {
              _q = v.trim();
              _offset = 0;
              _load();
            },
          ),
        ),
        const SizedBox(width: 12),
        ...widget.filters,
        const Spacer(),
        Text(_total == 0 ? '0 results' : '${_offset + 1}–$last of $_total',
            style: const TextStyle(color: Pal.muted, fontSize: 13)),
        IconButton(
          key: const ValueKey('prevPage'),
          icon: const Icon(Icons.chevron_left),
          onPressed: _offset == 0
              ? null
              : () {
                  _offset = (_offset - widget.pageSize).clamp(0, _total);
                  _load();
                },
        ),
        IconButton(
          key: const ValueKey('nextPage'),
          icon: const Icon(Icons.chevron_right),
          onPressed: _offset + widget.pageSize >= _total
              ? null
              : () {
                  _offset += widget.pageSize;
                  _load();
                },
        ),
      ]),
      const SizedBox(height: 8),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child:
              Text(errorText(_error!), style: const TextStyle(color: Pal.bad)),
        )
      else
        Expanded(
          child: Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Pal.line)),
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(
                        child: Text('Nothing found',
                            style: TextStyle(color: Pal.muted)))
                    : LayoutBuilder(
                        builder: (context, c) => SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: c.maxWidth),
                              child: DataTable(
                                showCheckboxColumn: false,
                                columns: [
                                  for (final c in widget.columns)
                                    DataColumn(label: Text(c))
                                ],
                                rows: [
                                  for (final r in _rows)
                                    DataRow(
                                      onSelectChanged: widget.onRow == null
                                          ? null
                                          : (_) => widget.onRow!(r),
                                      cells: widget.cells(r),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ),
    ]);
  }
}
