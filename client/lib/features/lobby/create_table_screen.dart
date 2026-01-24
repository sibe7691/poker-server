import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';

class CreateTableScreen extends ConsumerStatefulWidget {
  const CreateTableScreen({super.key});

  @override
  ConsumerState<CreateTableScreen> createState() => _CreateTableScreenState();
}

class _CreateTableScreenState extends ConsumerState<CreateTableScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tableIdController = TextEditingController();
  final _smallBlindController = TextEditingController(text: '1');
  final _bigBlindController = TextEditingController(text: '2');

  int _maxPlayers = 6;

  static const List<int> _maxPlayersOptions = [2, 4, 6, 8, 10];

  @override
  void dispose() {
    _tableIdController.dispose();
    _smallBlindController.dispose();
    _bigBlindController.dispose();
    super.dispose();
  }

  void _createTable() {
    if (!_formKey.currentState!.validate()) return;

    final gameController = ref.read(gameControllerProvider.notifier);

    final tableId = _tableIdController.text.trim();
    final smallBlind = int.tryParse(_smallBlindController.text);
    final bigBlind = int.tryParse(_bigBlindController.text);

    gameController.createTable(
      tableId: tableId,
      smallBlind: smallBlind,
      bigBlind: bigBlind,
      maxPlayers: _maxPlayers,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Table creation requested'),
        backgroundColor: PokerTheme.tableFelt,
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Table'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [PokerTheme.surfaceDark, PokerTheme.darkBackground],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildTableIdField(),
                  const SizedBox(height: 24),
                  _buildMaxPlayersSelector(),
                  const SizedBox(height: 24),
                  _buildBlindsSection(),
                  const SizedBox(height: 40),
                  _buildCreateButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PokerTheme.tableFelt.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.table_restaurant,
            size: 48,
            color: PokerTheme.goldAccent,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Set Up Your Table',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Configure your poker table settings',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildTableIdField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Table ID'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _tableIdController,
          decoration: const InputDecoration(
            hintText: 'Enter table ID',
            prefixIcon: Icon(Icons.tag),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a table ID';
            }
            if (value.trim().length < 2) {
              return 'ID must be at least 2 characters';
            }
            if (value.trim().length > 30) {
              return 'ID must be less than 30 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildMaxPlayersSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Max Players'),
        const SizedBox(height: 12),
        Row(
          children: _maxPlayersOptions.map((count) {
            final isSelected = _maxPlayers == count;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: count != _maxPlayersOptions.last ? 8 : 0,
                ),
                child: _PlayerCountChip(
                  count: count,
                  isSelected: isSelected,
                  onTap: () => setState(() => _maxPlayers = count),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBlindsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Blinds (optional)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _smallBlindController,
                decoration: const InputDecoration(
                  labelText: 'Small Blind',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  // Auto-set big blind to 2x small blind
                  final small = int.tryParse(value);
                  if (small != null && small > 0) {
                    _bigBlindController.text = (small * 2).toString();
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _bigBlindController,
                decoration: const InputDecoration(
                  labelText: 'Big Blind',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Blinds: ${_smallBlindController.text}/${_bigBlindController.text}',
          style: TextStyle(
            color: PokerTheme.goldAccent.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    return ElevatedButton(
      onPressed: _createTable,
      style: ElevatedButton.styleFrom(
        backgroundColor: PokerTheme.goldAccent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline),
          SizedBox(width: 8),
          Text(
            'CREATE TABLE',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white70,
      ),
    );
  }
}

class _PlayerCountChip extends StatelessWidget {
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlayerCountChip({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? PokerTheme.tableFelt : PokerTheme.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? PokerTheme.goldAccent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.white60,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'players',
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white70 : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
