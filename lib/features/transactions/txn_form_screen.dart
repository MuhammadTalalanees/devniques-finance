import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/formatters.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

const paymentMethods = ['Cash', 'Bank', 'Card', 'Online', 'Other'];

/// Add / edit a transaction. Both admin and staff can open this
/// (staff = add only; edit/delete is gated before navigation).
class TxnFormScreen extends ConsumerStatefulWidget {
  final Txn? existing;
  const TxnFormScreen({super.key, this.existing});

  @override
  ConsumerState<TxnFormScreen> createState() => _TxnFormScreenState();
}

class _TxnFormScreenState extends ConsumerState<TxnFormScreen> {
  late String _type;
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  String? _categoryId;
  String? _partyId;
  DateTime _date = DateTime.now();
  String _method = 'Cash';
  String? _receiptLocal;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? 'expense';
    if (e != null) {
      _amount.text = e.amount.toStringAsFixed(2);
      _desc.text = e.description;
      _categoryId = e.categoryId;
      _partyId = e.partyId;
      _date = e.date;
      _method = e.paymentMethod;
    }
  }

  Future<void> _pickReceipt() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 70);
    if (img != null) setState(() => _receiptLocal = img.path);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Enter a valid amount');
      return;
    }
    final profile = await ref.read(profileProvider.future);
    if (profile == null) {
      _snack('Not signed in');
      return;
    }
    setState(() => _busy = true);
    try {
      String? receiptUrl = widget.existing?.receiptUrl;
      String? receiptLocal = _receiptLocal;
      // Upload now if online; otherwise keep the local path for later sync.
      if (_receiptLocal != null) {
        try {
          receiptUrl = await ref
              .read(supaServiceProvider)
              .uploadReceipt(_receiptLocal!);
          receiptLocal = null;
        } catch (_) {
          // offline — will upload during sync
        }
      }
      final cats = await ref.read(categoryListProvider.future);
      final parties = await ref.read(partyListProvider.future);
      final cat = cats.where((c) => c.id == _categoryId);
      final party = parties.where((p) => p.id == _partyId);
      final now = DateTime.now();
      final txn = Txn(
        id: widget.existing?.id ?? newId(),
        type: _type,
        amount: amount,
        categoryId: _categoryId,
        categoryName: cat.isEmpty ? '' : cat.first.name,
        partyId: _partyId,
        partyName: party.isEmpty ? '' : party.first.name,
        date: _date,
        description: _desc.text.trim(),
        paymentMethod: _method,
        receiptUrl: receiptUrl,
        receiptLocal: receiptLocal,
        createdBy: widget.existing?.createdBy ?? profile.id,
        updatedAt: now,
      );
      final repo = ref.read(txnRepoProvider);
      if (_isEdit) {
        await repo.update(txn);
      } else {
        await repo.add(txn);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoryListProvider);
    final parties = ref.watch(partyListProvider);
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEdit ? 'Edit entry' : 'New entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'expense',
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward)),
              ButtonSegment(
                  value: 'income',
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward)),
            ],
            selected: {_type},
            onSelectionChanged: (s) =>
                setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Amount (Rs)', prefixText: 'Rs '),
          ),
          const SizedBox(height: 12),
          cats.when(
            data: (list) {
              final items = list
                  .where((c) => c.matches(_type))
                  .toList();
              return DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration:
                    const InputDecoration(labelText: 'Category'),
                items: items
                    .map((c) => DropdownMenuItem(
                        value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _categoryId = v),
              );
            },
            loading: () =>
                const LinearProgressIndicator(),
            error: (_, __) =>
                const Text('Could not load categories'),
          ),
          const SizedBox(height: 12),
          parties.when(
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _partyId,
              decoration: const InputDecoration(
                  labelText: 'Party (optional)'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('— None —')),
                ...list.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.name} (${p.kind})'))),
              ],
              onChanged: (v) =>
                  setState(() => _partyId = v),
            ),
            loading: () =>
                const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text(fmtDate(_date)),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now()
                    .add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration:
                const InputDecoration(labelText: 'Payment method'),
            items: paymentMethods
                .map((m) =>
                    DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) =>
                setState(() => _method = v ?? 'Cash'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Description / notes'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long),
            title: Text(_receiptLocal != null
                ? 'Photo attached'
                : (widget.existing?.receiptUrl != null
                    ? 'Receipt on file'
                    : 'Attach receipt photo')),
            trailing: _receiptLocal != null
                ? Image.file(File(_receiptLocal!),
                    width: 48, height: 48, fit: BoxFit.cover)
                : null,
            onTap: _pickReceipt,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? 'Save changes' : 'Add entry'),
          ),
        ],
      ),
    );
  }
}
