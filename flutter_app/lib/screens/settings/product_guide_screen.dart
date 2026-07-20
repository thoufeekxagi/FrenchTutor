import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/passeport_primary_button.dart';

class ProductGuideScreen extends StatefulWidget {
  const ProductGuideScreen({super.key});

  @override
  State<ProductGuideScreen> createState() => _ProductGuideScreenState();
}

class _ProductGuideScreenState extends State<ProductGuideScreen> {
  final _controller = PageController();
  var _index = 0;

  static const _steps = [
    _GuideStep(
      icon: CupertinoIcons.flag_fill,
      title: 'Start with Today’s Mission',
      body:
          'Open Today for one useful French mission. It tells you what is next, why it matters, and how long it will take.',
    ),
    _GuideStep(
      icon: CupertinoIcons.lightbulb_fill,
      title: 'Read “Chosen because”',
      body:
          'This explanation comes from your recent practice and learning goals. It is not a generic recommendation.'
    ),
    _GuideStep(
      icon: CupertinoIcons.rectangle_stack_fill,
      title: 'Practise one card at a time',
      body:
          'Vocabulary, grammar, and guided listening stay focused on the current card. You never need to guess what to do next.',
    ),
    _GuideStep(
      icon: CupertinoIcons.speaker_2_fill,
      title: 'Replay any audio',
      body:
          'Use the replay control when you want to hear a word, line, or scene again. Repetition is always available.',
    ),
    _GuideStep(
      icon: CupertinoIcons.mic_fill,
      title: 'Use a precise voice command',
      body:
          'Say “Next card” to move forward. Background noise, conversation, “yes,” and unclear speech never move a card. If recognition misses your command, use the visible Next button.',
    ),
    _GuideStep(
      icon: CupertinoIcons.person_2_fill,
      title: 'Use the same language with Marie',
      body:
          'The final roleplay uses the scenario and language you just practised. Marie responds in character, while the app keeps the mission structure.',
    ),
    _GuideStep(
      icon: CupertinoIcons.chart_bar_square_fill,
      title: 'Watch your progress grow',
      body:
          'Progress reflects the work you complete. More practice is a normal part of learning, not a failure.'
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _steps.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: DesignTokens.durationMedium,
      curve: DesignTokens.curveStandard,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        backgroundColor: DesignTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(CupertinoIcons.xmark),
          tooltip: 'Close guide',
        ),
        title: Text('How ParleSprint works', style: DesignTokens.display(20)),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            children: [
              Row(
                children: List.generate(
                  _steps.length,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: DesignTokens.durationFast,
                      height: 4,
                      margin: EdgeInsets.only(
                        right: index == _steps.length - 1 ? 0 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: index <= _index
                            ? DesignTokens.primary
                            : DesignTokens.canvasDim,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusPill,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (_, index) {
                    final item = _steps[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: DesignTokens.infoSoft,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusCard,
                            ),
                          ),
                          child: Icon(
                            item.icon,
                            size: 32,
                            color: DesignTokens.info,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(item.title, style: DesignTokens.display(30)),
                        const SizedBox(height: 12),
                        Text(
                          item.body,
                          style: DesignTokens.body(
                            17,
                          ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
                        ),
                        if (index == 4) ...[
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(DesignTokens.space4),
                            decoration: BoxDecoration(
                              color: DesignTokens.surface,
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusCard,
                              ),
                              border: Border.all(color: DesignTokens.hairline),
                            ),
                            child: Text(
                              'Say exactly: “Next card”',
                              style: DesignTokens.body(
                                18,
                                weight: FontWeight.w700,
                              ).copyWith(color: DesignTokens.primary),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              Text(
                '${_index + 1} of ${_steps.length}',
                style: DesignTokens.body(
                  13,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.slateDim),
              ),
              const SizedBox(height: 12),
              PasseportPrimaryButton(
                label: _index == _steps.length - 1
                    ? 'Start practising'
                    : 'Next',
                icon: _index == _steps.length - 1
                    ? CupertinoIcons.checkmark
                    : CupertinoIcons.arrow_right,
                onPressed: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStep {
  const _GuideStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
