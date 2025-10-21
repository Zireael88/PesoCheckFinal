import 'package:flutter/material.dart';

class InstructionsScreen extends StatefulWidget {
  const InstructionsScreen({super.key});

  @override
  State<InstructionsScreen> createState() => _InstructionsScreenState();
}

class _InstructionsScreenState extends State<InstructionsScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _goTo(int index) {
    if (index < 0 || index > 2) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _dot(int index) {
    final bool isActive = _currentPage == index;
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Colors.white : Colors.white38,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF232426),
      appBar: AppBar(
        title: const Text('PesoCheck'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                // Removed decorative box styling to avoid boxed look
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Instructions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 40,
                      ),
                    ),
                    const SizedBox(height: 35),
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (i) => setState(() => _currentPage = i),
                        children: [
                          const _InstructionSlide(
                            imageAsset: 'assets/instruction/insphoto1.png',
                            captionTop: 'NGC                eNGC',
                            captionBottom: 'PesoCheck is limited to NGC/\neNGC banknotes and only\naccepts ₱50, ₱100, ₱500, and\n₱1000 denominations.',
                            showGoodBadRow: false,
                            accentColor: Colors.greenAccent,
                          ),
                          const _InstructionSlide(
                            imageAsset: 'assets/instruction/insphoto2.png',
                            captionBottom: 'Upload clear images of the\nbanknotes; you are encouraged\nto use flash under low light.',
                            showGoodBadRow: true,
                            good: true,
                          ),
                          const _InstructionSlide(
                            imageAsset: 'assets/instruction/insphoto3.png',
                            captionBottom: 'Examples of what not to do.',
                            showGoodBadRow: true,
                            good: false,
                            imageAspectRatio: 1.0,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => _goTo(_currentPage - 1),
                        ),
                        _dot(0),
                        _dot(1),
                        _dot(2),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => _goTo(_currentPage + 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionSlide extends StatelessWidget {
  final String imageAsset;
  final String? captionTop;
  final String captionBottom;
  final bool showGoodBadRow;
  final bool good;
  final Color? accentColor;
  final double imageAspectRatio;

  const _InstructionSlide({
    required this.imageAsset,
    this.captionTop,
    required this.captionBottom,
    required this.showGoodBadRow,
    this.good = true,
    this.accentColor,
    this.imageAspectRatio = 4 / 3,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          if (captionTop != null) ...[
            Text(
              captionTop!,
              style: TextStyle(
                color: accentColor ?? (showGoodBadRow
                    ? (good ? Colors.greenAccent : Colors.redAccent)
                    : Colors.white70),
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          AspectRatio(
            aspectRatio: imageAspectRatio,
            child: Image.asset(
              imageAsset,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 12),
          if (showGoodBadRow)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  good ? Icons.check_circle : Icons.cancel,
                  color: good ? Colors.greenAccent : Colors.redAccent,
                ),
                if (good) ...[
                  const SizedBox(width: 32),
                  const Icon(Icons.check_circle, color: Colors.greenAccent),
                ],
              ],
            ),
          const SizedBox(height: 12),
          Text(
            captionBottom,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accentColor ?? (showGoodBadRow
                  ? (good ? Colors.greenAccent : Colors.redAccent)
                  : Colors.white70),
              fontSize: 20,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}


