import 'dart:async';

import 'package:flutter/material.dart';

class FilterHistoryTextField extends StatefulWidget {
  final TextEditingController controller;
  final String filterText;
  final String hintText;
  final int maxHistory;
  final ValueChanged<String>? onChanged;

  const FilterHistoryTextField({
    super.key,
    required this.controller,
    required this.filterText,
    required this.hintText,
    this.maxHistory = 5,
    this.onChanged,
  });

  @override
  State<FilterHistoryTextField> createState() => _FilterHistoryTextFieldState();
}

class _FilterHistoryTextFieldState extends State<FilterHistoryTextField> {
  final List<String> _history = [];
  Timer? _historyTimer;

  @override
  void dispose() {
    _historyTimer?.cancel();
    super.dispose();
  }

  void _rememberCurrent() {
    final value = widget.controller.text.trim();
    if (value.isEmpty) return;

    setState(() {
      _history.removeWhere((item) => item.toLowerCase() == value.toLowerCase());
      _history.insert(0, value);
      if (_history.length > widget.maxHistory) {
        _history.removeRange(widget.maxHistory, _history.length);
      }
    });
  }

  void _applyHistory(String value) {
    _historyTimer?.cancel();
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
    _rememberCurrent();
  }

  void _clearFilter() {
    _historyTimer?.cancel();
    _rememberCurrent();
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    _historyTimer?.cancel();
    if (value.trim().isEmpty) return;
    _historyTimer = Timer(const Duration(seconds: 3), _rememberCurrent);
  }

  void _handleSubmitted(String value) {
    _historyTimer?.cancel();
    _rememberCurrent();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _buildSuffix(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      style: const TextStyle(fontSize: 13),
      textInputAction: TextInputAction.search,
      onChanged: _handleChanged,
      onSubmitted: _handleSubmitted,
    );
  }

  Widget? _buildSuffix() {
    if (widget.filterText.isEmpty && _history.isEmpty) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_history.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: '过滤历史',
            icon: const Icon(Icons.history, size: 18),
            onSelected: _applyHistory,
            itemBuilder: (context) => [
              for (final item in _history)
                PopupMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        if (widget.filterText.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            tooltip: '清除过滤',
            onPressed: _clearFilter,
          ),
      ],
    );
  }
}
