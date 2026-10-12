# Screen map (generated)

Regenerate with `python3 flutter_app/tool/screen_map.py`. Do not edit by hand.
Rule: read this, then read the file. Never assume a key, label or route.

## `lib/screens/auth/auth_screen.dart`
- widgets: AuthScreen
- tap handlers: 0

## `lib/screens/auth/password_recovery_screen.dart`
- widgets: PasswordRecoveryScreen
- tap handlers: 2

## `lib/screens/auth/speak_auth_screen.dart`
- widgets: SpeakAuthScreen
- tap handlers: 5

## `lib/screens/exam/exam_practice_screen.dart`
- widgets: ExamPracticeScreen, _ExamHeader, _QuestionBlock, _OptionRow, _ReviewAnswerLine, _ExamSurface
- tap handlers: 7
- labels: 'Correct answer', 'Leave practice', 'Your answer'

## `lib/screens/exam/exam_readiness_screen.dart`
- widgets: ExamReadinessScreen, _ChoiceCard, _SkillLauncher, _RecentExamPractice
- opens: ListeningLabScreen, MocksScreen, ReadingLibraryScreen, WritingLabScreen
- tap handlers: 10

## `lib/screens/grammar/grammar_complete_lesson_screen.dart`
- widgets: GrammarCompleteLessonScreen
- tap handlers: 5
- labels: 'Close grammar session'

## `lib/screens/grammar/grammar_curriculum_home_screen.dart`
- widgets: GrammarCurriculumHomeScreen, _CurrentLessonCard, _ModeCard, _LessonCard, _AdvancedGenerationCard, _ReviewMistakesCard, _LevelRow
- opens: GrammarLessonFlowScreen
- tap handlers: 13

## `lib/screens/grammar/grammar_lesson_flow_screen.dart`
- widgets: GrammarLessonFlowScreen, _ExerciseCard, _AnswerChoice, _WordTile, _RepairChip, _StepLabel, _PreviewRow, _ReviewLine
- tap handlers: 11
- labels: 'Close grammar lesson', 'FIX ONE PART', 'Grammar repair', 'LESSON REVIEW', 'MAKE A SENTENCE', 'PICK THE RIGHT WORD', 'Right form', 'Sentence order', 'WRITE YOUR OWN'

## `lib/screens/grammar/grammar_roleplay_lesson_screen.dart`
- widgets: GrammarRoleplayLessonScreen
- tap handlers: 3
- labels: 'Close grammar roleplay'

## `lib/screens/grammar/grammar_v2_home_screen.dart`
- widgets: GrammarV2HomeScreen, _GrammarSessionCard
- opens: GrammarV2LessonScreen, V3SettingsScreen
- tap handlers: 7
- labels: 'Back', 'Grammar settings'

## `lib/screens/grammar/grammar_v2_lesson_screen.dart`
- widgets: GrammarV2LessonScreen, _PromptCard, _PartnerCard, _ChoiceTile, _WordChip, _AnswerTray, _InfoCard
- tap handlers: 12
- labels: 'Close grammar session'

## `lib/screens/history/all_history_screen.dart`
- widgets: AllHistoryScreen
- opens: HistoryScreen
- tap handlers: 2

## `lib/screens/history/history_screen.dart`
- widgets: HistoryScreen
- tap handlers: 1
- labels: 'Back'

## `lib/screens/home/daily_summary_card.dart`
- widgets: DailySummaryCard
- tap handlers: 0

## `lib/screens/home/dashboard_screen.dart`
- widgets: DashboardScreen, _Metric, _StudyBlockRow
- opens: AllHistoryScreen, AlphabetLabScreen, GrammarLabScreen, HistoryScreen, LabsScreen, LiaisonLabScreen, ListeningLabScreen, NotesReviewScreen, ReadingLibraryScreen, SettingsScreen, SpeakingPracticeScreen, WeeklyReviewScreen, WritingLabScreen
- tap handlers: 26
- labels: 'Explore practice', 'Grammar', 'Liaison', 'Listening', 'Open settings', 'Pronunciation', 'Reading', 'Review notes', 'Roleplay', 'Speaking', 'Vocabulary', 'Writing', 'study steps today'

## `lib/screens/home/today_mission_widget.dart`
- widgets: TodayMissionWidget, _MissionMeta, _MissionProgress, _CategoryDot, _MissionComplete, _MissionNotice
- opens: GrammarLabScreen, ListeningLabScreen, SpeakingPracticeScreen, VocabLabScreen, WritingLabScreen
- tap handlers: 3
- labels: 'Try again'

## `lib/screens/home/weekly_review_screen.dart`
- widgets: WeeklyReviewScreen
- opens: LabsScreen, SpeakReviewScreen, VocabLabScreen, VocabularyFlashcardsScreen, WritingLabScreen
- tap handlers: 16
- labels: 'Back', 'Next week', 'Previous week'

## `lib/screens/labs/alphabet_lab_screen.dart`
- widgets: AlphabetLabScreen, _AlphabetDeckScreen, _CompactLetterCard, _AlphabetQuiz, _QuestionCard
- tap handlers: 7
- labels: 'Check answers', 'Done', 'Take the quick review'

## `lib/screens/labs/connectors_lab_screen.dart`
- widgets: ConnectorsLabScreen, _ConnectorsQuizView
- tap handlers: 6
- labels: 'Done', 'Take the 10-question quiz'

## `lib/screens/labs/grammar_lab_screen.dart`
- widgets: GrammarLabScreen
- opens: GrammarV2LessonScreen
- tap handlers: 0

## `lib/screens/labs/labs_screen.dart`
- widgets: LabsScreen, _RecommendedPractice, _LabTile
- tap handlers: 23
- labels: 'Alphabet', 'Connectors', 'Flashcards', 'Grammar', 'Liaison', 'Listening', 'Practice today’s vocabulary', 'Roleplay', 'Speaking mock', 'Vocabulary', 'Writing'

## `lib/screens/labs/liaison_lab_screen.dart`
- widgets: LiaisonLabScreen, _ContinueCard, _LessonTile, _RecentTile, _TapCard, _CircleIcon
- opens: GrammarWorkshopScreen, LiaisonLessonScreen
- tap handlers: 9
- labels: 'Generate with AI'

## `lib/screens/labs/liaison_lesson_screen.dart`
- widgets: LiaisonLessonScreen, _AudioButton, _ChoiceButton, _MessageCard
- tap handlers: 19
- labels: 'Next phrase', 'Practice more', 'Replay'

## `lib/screens/labs/listening_lab_screen.dart`
- widgets: ListeningLabScreen, _ListeningSectionLabel, _DirectCourseLoading, _GenerateStoryTile, _ListeningSelectionPill, _ListeningChoiceSheet, _TopicChipRow, _ContinueStoryCard, _StoryBookCard, _StoryCover, _EmptyLibraryNote
- opens: _lessonScreen
- tap handlers: 11
- labels: 'Audio format', 'Music', 'Narration', 'Story', 'Surprise me', 'Topic'

## `lib/screens/labs/roleplay_lab_screen.dart`
- widgets: RoleplayLabScreen, _RoleplayStartSection, _ScenarioChipRow, _RoleplayTile, _EmptyRoleplayLibraryNote
- opens: RoleplayReviewScreen
- tap handlers: 5
- labels: 'Build roleplay'

## `lib/screens/labs/vocab_lab_screen.dart`
- widgets: VocabLabScreen, _VocabularySetCard, _VocabularySetMakerSheet
- opens: V3SettingsScreen, VocabularyFlashcardsScreen
- tap handlers: 8
- labels: 'Back', 'Make five words', 'Start lesson', 'Vocabulary settings'

## `lib/screens/labs/vocabulary_flashcards_screen.dart`
- widgets: VocabularyFlashcardsScreen
- tap handlers: 14
- labels: 'Done', 'Go back', 'Meaning shown', 'Practice more', 'Replay word'

## `lib/screens/labs/writing_course_home_screen.dart`
- widgets: WritingCourseHomeScreen, _LevelBadge, _WritingLessonCard
- opens: V3SettingsScreen, WritingCourseLessonScreen
- tap handlers: 7
- labels: 'Back', 'Writing settings'

## `lib/screens/labs/writing_lab_screen.dart`
- widgets: WritingLabScreen, _GeneratedWritingTaskTile, _LevelBadge, _ModeCard, _CurriculumTile, _SubmissionTile
- opens: WritingWorkshopScreen
- tap handlers: 11
- labels: 'Generate a personalized task', 'New writing practice'

## `lib/screens/lessons/flashcard_session_screen.dart`
- widgets: FlashcardSessionScreen
- tap handlers: 5
- labels: 'Done', 'Normal', 'Say it', 'Slow'

## `lib/screens/lessons/grammar_workshop_screen.dart`
- widgets: GrammarWorkshopScreen, _StepKicker, _ConjugationCard, _ChoiceTile, _ReviewActions, _EmptyState
- tap handlers: 11
- labels: 'Choose the form', 'Listen once', 'Lock it in', 'Notice it in context', 'Understand the pattern', 'Use it yourself'

## `lib/screens/lessons/listening_practice_screen.dart`
- widgets: ListeningPracticeScreen, _ListeningImmersiveBackground, _ListeningTopBar, _ListeningRoundButton, _ListeningPlayerDock, _ListeningMiniPlayer, _ListeningUtilityButton, _ListeningTranscriptLines, _ListeningFullscreenTranscript, _ListeningStageIslandTabs, _ListeningProgressControls, _NightPanel, _NightPrimaryButton, _NightAudioIsland, _IslandDivider, _IslandCircle, _IslandText, _ListeningSettingsSheet, _NightSettingChoice, _NightSwitchRow, _StageEyebrow, _ChoiceButton, _EmptyStage
- tap handlers: 53
- labels: '02 · Quick check', '03 · Tune your ear', '04 · Active listening', '05 · Shadowing', 'Audio control', 'Auto-play word audio', 'Back', 'Check the word', 'Complete', 'Finish listening', 'Grammar', 'Hide lyrics', 'Highlight words', 'Keywords', 'Listening settings', 'Lyrics', 'Play dictation line', 'Play target line', 'Playback speed', 'Replay', 'See my listening recap', 'Text size', 'Translate', 'Underline words', 'Word translations'

## `lib/screens/lessons/reading_storybook_screen.dart`
- widgets: ReadingStorybookScreen, _ProgressHeader, _ActionFooter, _BookHero, _ReadingMap, _SectionIntro, _SentenceCard, _ExplanationCard, _QuizCard, _EmptyReadingBody
- tap handlers: 14
- labels: 'GRAMMAR', 'SOUND', 'Stop reading aloud'

## `lib/screens/lessons/story_reader_screen.dart`
- widgets: StoryReaderScreen, _StoryBookHeader, _HeroIconButton, _GrammarExplanationCard, _ConjugationTable, _GrammarCueCard, _ReadingCallState, _StoryStageIsland, _AudioControlBar, _StoryNextBar, _StorySettingsSheet, _ComingSoon
- tap handlers: 30
- labels: 'Back', 'Grammar', 'Keywords', 'Quiz', 'Replay sentence', 'Replay this sentence with Marie', 'Stop audio', 'Story settings', 'Words'

## `lib/screens/lessons/writing_course_lesson_screen.dart`
- widgets: WritingCourseLessonScreen, ExpandedOrWrap, _AnswerToken, _WordChip, _ChoiceRow, _PartnerBubble, _LearnerBubble, _InlineNotice
- tap handlers: 27
- keys: `${widget.lesson.id}-$_index`
- labels: 'Close writing lesson', 'Grammar', 'Hear the correct French sentence', 'Hear the current French sentence', 'Hint', 'Listen to Marie', 'Redo reply'

## `lib/screens/lessons/writing_task_screen.dart`
- widgets: WritingTaskScreen
- tap handlers: 7
- labels: 'Done'

## `lib/screens/lessons/writing_workshop_screen.dart`
- widgets: WritingWorkshopScreen, _Footer, _KeyboardAccessory, _SectionIntro, _WritingResultCard, _SubmissionTextCard, _WritingScoreCard, _ScoreRow, _MiniPrompt, _DraftField, _FocusList, _CorrectionCard, _BulletCard, _ErrorText, _FeedbackPendingBody
- tap handlers: 14
- labels: 'Hear the improved version', 'Next move', 'Start your answer', 'Try feedback again', 'What worked', 'Your French draft', 'Your improved sentence'

## `lib/screens/main_tab_screen.dart`
- widgets: MainTabScreen
- opens: V3SettingsScreen
- tap handlers: 2
- labels: 'Course', 'Home', 'Photo tutor', 'Practice', 'Profile'

## `lib/screens/mocks/mocks_screen.dart`
- widgets: MocksScreen
- opens: SessionScreen
- tap handlers: 5
- labels: 'Begin mock', 'Retry scoring'

## `lib/screens/notes/notes_review_screen.dart`
- widgets: NotesReviewScreen, _NoteRow
- tap handlers: 2

## `lib/screens/onboarding/ai_consent_screen.dart`
- widgets: AiConsentScreen
- tap handlers: 2

## `lib/screens/onboarding/onboarding_screen.dart`
- widgets: OnboardingScreen, _RecapMetric, _RecapWordsMetric, _BrandWordmark, _PreparingPane, _PromiseRow, _HeaderGutter
- opens: SpeakingPracticeScreen
- tap handlers: 20
- labels: '15 min', '30 min', '5 min', 'A1 · Just starting', 'A2 · I know the basics', 'B1 · I can hold a conversation', 'B2 · Polishing', 'Build my plan', 'Build the foundations', 'Continue', 'Everyday French', 'TEF / TCF Canada', 'practice time', 'times you spoke'

## `lib/screens/onboarding/speak_onboarding_screen.dart`
- widgets: SpeakOnboardingScreen
- opens: SpeakingPracticeScreen
- tap handlers: 19
- keys: `reminder-hour-wheel`, `reminder-minute-wheel`
- labels: 'Hour', 'Minute'

## `lib/screens/onboarding/v3_onboarding_screen.dart`
- widgets: V3OnboardingScreen
- tap handlers: 8
- labels: 'A1', 'A2', 'B1', 'B2', 'Deep', 'Everyday French', 'Quick', 'Standard', 'TEF Canada'

## `lib/screens/onboarding/widgets/apple_goal_view.dart`
- widgets: AppleGoalView, _TopStepHeader, _LuxuryGoalCard
- tap handlers: 4

## `lib/screens/onboarding/widgets/apple_level_view.dart`
- widgets: AppleLevelView, _TopStepHeader, _LevelCard, _SessionLengthSegmented
- tap handlers: 6
- labels: '15 min', '30 min', '5 min'

## `lib/screens/onboarding/widgets/apple_welcome_view.dart`
- widgets: AppleWelcomeView, _BrandHeader, _ValuePropositionCard, _PrimaryActionButton, _SecondarySignInButton
- tap handlers: 4

## `lib/screens/path/learning_graph_view.dart`
- widgets: FingerprintView
- tap handlers: 2
- keys: `legend`
- labels: 'Reset fingerprint view', 'Reset view'

## `lib/screens/path/path_screen.dart`
- widgets: PathScreen, _BandHeader, _CompetencyNode, _EmptyPath
- tap handlers: 1

## `lib/screens/pathway/agent_led_grammar_screen.dart`
- widgets: AgentLedGrammarScreen
- tap handlers: 5
- labels: 'End', 'End grammar practice', 'Next sentence'

## `lib/screens/pathway/agent_led_listening_screen.dart`
- widgets: AgentLedListeningScreen, _RoleplaySceneHeader, _RoleplayFinishPrompt
- tap handlers: 14
- labels: 'End', 'End listening practice', 'End roleplay practice', 'Finish scene'

## `lib/screens/pathway/agent_led_vocab_screen.dart`
- widgets: AgentLedVocabScreen
- tap handlers: 7
- labels: 'End', 'End vocabulary practice', 'Next word', 'Show today'

## `lib/screens/pathway/roleplay_review_screen.dart`
- widgets: RoleplayReviewScreen, _SectionLabel
- tap handlers: 7
- keys: `quiz`, `recap`
- labels: 'Close', 'Done', 'Next'

## `lib/screens/practice/v3_practice_screen.dart`
- widgets: V3PracticeScreen
- opens: ExamReadinessScreen, SpeakReviewScreen, screen, speaking
- tap handlers: 6

## `lib/screens/profile/v3_profile_screen.dart`
- widgets: V3ProfileScreen
- opens: AllHistoryScreen, FrenchFingerprintScreen, NotesReviewScreen, ProgressScreen, SpeakRoadmapScreen, StreakCalendarScreen, V3SettingsScreen
- tap handlers: 8
- labels: 'Settings', 'current level', 'day streak', 'sessions'

## `lib/screens/progress/progress_screen.dart`
- widgets: ProgressScreen
- opens: AllHistoryScreen, HistoryScreen, PathScreen
- tap handlers: 5
- labels: 'Back'

## `lib/screens/reading/reading_library_screen.dart`
- widgets: ReadingLibraryScreen, _DirectReadingLoading, _GenerateReadingTile, _ContinueReadingCard, _PreviousStoryRow, _ReadingCover
- opens: ExamPracticeScreen, StoryReaderScreen
- tap handlers: 6

## `lib/screens/scan/camera_capture_screen.dart`
- widgets: CameraCaptureScreen
- tap handlers: 2
- labels: 'Close camera'

## `lib/screens/scan/scan_screen.dart`
- widgets: ScanScreen, _EmptyState, _ScanMessageBubble, _NewScanSessionDialog, _ScanSessionPickerDialog, _ScanSessionRow, _ScanDialogButton, _ScanDialogCloseButton, _ScanComposer, _ScanHeaderButton, _ComposerIconButton
- tap handlers: 16
- labels: 'Add a photo or PDF', 'Cancel', 'Choose from Photos', 'Close', 'Import a PDF', 'Photo tutor sessions', 'Send question', 'Start a new photo tutor session', 'Start a new session', 'Start new session', 'Take a photo'

## `lib/screens/session/session_screen.dart`
- widgets: SessionScreen
- tap handlers: 9
- labels: 'End', 'End session'

## `lib/screens/settings/orchestration_lab_screen.dart`
- widgets: OrchestrationLabScreen, _ToggleRow
- tap handlers: 6
- labels: '20m', '2h', '45m', '90m', 'Can speak aloud', 'Network available', 'Persist competency states and generate today\\'

## `lib/screens/settings/privacy_ai_screen.dart`
- widgets: PrivacyAiScreen
- tap handlers: 10

## `lib/screens/settings/product_guide_screen.dart`
- widgets: ProductGuideScreen
- tap handlers: 2
- labels: 'Close guide'

## `lib/screens/settings/settings_screen.dart`
- widgets: SettingsScreen, _ChoiceRow, _ModernCard, _LegalLinkRow, _SettingsRow, _StepperButton
- opens: OrchestrationLabScreen, SpeakPaywallScreen
- tap handlers: 31
- labels: 'Access status', 'Account name', 'Days left', 'Email', 'English / French mix', 'Feedback', 'Goal', 'Hour', 'Level', 'Minute', 'Plan', 'Privacy Policy', 'Renews', 'Session length', 'Signed in with', 'Terms of Service', 'Tracked speaking today', 'Tutor speaking pace', 'Verification', 'Version'

## `lib/screens/speak/french_fingerprint_screen.dart`
- widgets: FrenchFingerprintScreen, _FingerprintStats, _SignalStrip
- tap handlers: 1
- labels: 'Back'

## `lib/screens/speak/live_tutor_setup_screen.dart`
- widgets: LiveTutorSetupScreen
- opens: SessionScreen
- tap handlers: 2
- labels: 'Back', 'Level', 'Style', 'Topic'

## `lib/screens/speak/smart_review_lesson_screen.dart`
- widgets: SmartReviewLessonScreen
- tap handlers: 4
- labels: 'Start guided review'

## `lib/screens/speak/speak_advanced_settings_screen.dart`
- widgets: SpeakAdvancedSettingsScreen
- tap handlers: 15
- labels: 'Hour', 'Minute'

## `lib/screens/speak/speak_challenge_screen.dart`
- widgets: SpeakChallengeScreen
- tap handlers: 0

## `lib/screens/speak/speak_course_activity_screen.dart`
- widgets: SpeakCourseActivityScreen
- opens: AlphabetLabScreen, ConnectorsLabScreen, GrammarV2LessonScreen, LiaisonLabScreen, ListeningPracticeScreen, SpeakReviewScreen, SpeakingLessonFlowScreen, StoryReaderScreen, VocabularyFlashcardsScreen, WritingCourseLessonScreen, screen
- tap handlers: 2
- labels: 'Back to course'

## `lib/screens/speak/speak_course_vocabulary_screen.dart`
- widgets: SpeakCourseVocabularyScreen, _ModeCard
- opens: VocabularyFlashcardsScreen
- tap handlers: 4

## `lib/screens/speak/speak_free_talk_screen.dart`
- widgets: SpeakFreeTalkScreen
- opens: SpeakingLessonFlowScreen
- tap handlers: 3
- labels: 'Back'

## `lib/screens/speak/speak_home_screen.dart`
- widgets: SpeakHomeScreen, _ModePill, _PracticeOptionCard, _FeaturedSessionCard, _TutorActivityCard, _LessonActivityCard, _ActivityCardShell
- opens: SpeakCourseActivityScreen, SpeakProfileScreen, SpeakSettingsScreen, SpeakingHubScreen, SpeakingPracticeScreen, destination
- tap handlers: 18
- labels: 'Open profile'

## `lib/screens/speak/speak_lesson_screen.dart`
- widgets: SpeakLessonScreen
- opens: SessionScreen
- tap handlers: 2
- labels: 'Start speaking'

## `lib/screens/speak/speak_practice_screen.dart`
- widgets: SpeakPracticeScreen
- opens: ExamReadinessScreen, SavedSpeakingTranscriptScreen, SpeakReviewScreen, SpeakRoadmapScreen, screen
- tap handlers: 8
- labels: 'Course', 'Open review from recent practice sessions', 'Practice'

## `lib/screens/speak/speak_profile_screen.dart`
- widgets: SpeakProfileScreen
- opens: AllHistoryScreen, FrenchFingerprintScreen, NotesReviewScreen, ProgressScreen, SpeakRoadmapScreen, SpeakSettingsScreen, StreakCalendarScreen
- tap handlers: 5
- labels: 'Back', 'LONGEST\\nSTREAK', 'SENTENCES\\nLIFETIME', 'Settings', 'TIME\\nSTUDIED'

## `lib/screens/speak/speak_quick_practice_screen.dart`
- widgets: SpeakQuickPracticeScreen
- opens: GrammarLabScreen, SpeakFreeTalkScreen, VocabLabScreen
- tap handlers: 5
- labels: 'Back'

## `lib/screens/speak/speak_review_screen.dart`
- widgets: SpeakReviewScreen, SavedSpeakingTranscriptScreen, SavedPracticeSessionScreen, SpeakReviewLaunchScreen
- opens: ListeningPracticeScreen, SmartReviewLessonScreen, SpeakReviewLaunchScreen, SpeakReviewScreen, SpeakingLessonFlowScreen, SpeakingPracticeScreen, StoryReaderScreen, WritingCourseLessonScreen, isSpeaking
- tap handlers: 10
- labels: 'Close saved transcript', 'Open and practise again', 'Open saved practice', 'Try again'

## `lib/screens/speak/speak_roadmap_screen.dart`
- widgets: SpeakRoadmapScreen, _LessonPreparationIndicator
- opens: _screenFor
- tap handlers: 5
- labels: 'All sessions', 'Course options', 'Creating lesson', 'Current unit', 'Retry lesson preparation'

## `lib/screens/speak/speak_roleplay_screen.dart`
- widgets: SpeakRoleplayScreen
- tap handlers: 4
- labels: 'Back', 'Play phrase', 'Save roleplay'

## `lib/screens/speak/speak_settings_screen.dart`
- widgets: SpeakSettingsScreen, _TutorPickerSheet
- opens: SpeakAdvancedSettingsScreen, SpeakPaywallScreen
- tap handlers: 17

## `lib/screens/speak/speak_tutor_prototype_screen.dart`
- widgets: SpeakTutorPrototypeScreen
- opens: SessionScreen
- tap handlers: 5
- labels: 'Add line', 'Close'

## `lib/screens/speak/speak_ui.dart`
- widgets: SpeakScaffold, SpeakHeader, SpeakPill, SpeakSectionTitle, SpeakCard, SpeakPrimaryButton, SpeakProgressBar, SpeakStat
- tap handlers: 3

## `lib/screens/speak/speaking_course_home_screen.dart`
- widgets: SpeakingCourseHomeScreen, _SpeakingTopicCard
- opens: SpeakRoleplayScreen, SpeakSettingsScreen, SpeakingLessonFlowScreen
- tap handlers: 8
- labels: 'Back', 'Speaking settings'

## `lib/screens/speak/speaking_flow_screen.dart`
- widgets: SpeakingHubScreen, SpeakingLessonDetailScreen, SpeakingRoleplayDetailScreen, _SpeakingDarkPage
- opens: SavedSpeakingTranscriptScreen, SpeakCourseActivityScreen, SpeakFreeTalkScreen, SpeakQuickPracticeScreen, SpeakSettingsScreen, SpeakingLessonFlowScreen, SpeakingPracticeScreen
- tap handlers: 18
- labels: 'Back', 'Speaking settings', 'Start lesson', 'Start roleplay'

## `lib/screens/speak/speaking_lesson_flow_screen.dart`
- widgets: SpeakingLessonFlowScreen
- tap handlers: 20
- labels: 'Close lesson', 'MARIE', 'Next phrase', 'Play Marie’s line', 'Play phrase', 'Practice more', 'Replay target', 'Save lesson', 'YOU'

## `lib/screens/speak/speaking_practice_screen.dart`
- widgets: SpeakingPracticeScreen, _PlanPreviewCard, _PlanTag, _SelectionTile, _CompactSelection, _ErrorPanel
- opens: SavedSpeakingTranscriptScreen, SessionScreen, SpeakRoadmapScreen
- tap handlers: 14
- labels: 'Back', 'Course', 'Goal', 'Level', 'Practice', 'Practice style', 'Time', 'Topic'

## `lib/screens/speak/speaking_studio_screen.dart`
- widgets: SpeakingStudioScreen, _ModePill, _QuickStartCard, _CourseSessionRow
- opens: LiveTutorSetupScreen, SpeakCourseActivityScreen, SpeakProfileScreen, SpeakReviewScreen, SpeakSettingsScreen, WeeklyReviewScreen, destination
- tap handlers: 12
- labels: 'Live tutor', 'Open profile', 'Open speaking settings', 'Report', 'Review', 'Speaking settings', 'Warm-up'

## `lib/screens/speak/streak_calendar_screen.dart`
- widgets: StreakCalendarScreen, _Weekday, _DayCell, _LegendDot
- tap handlers: 1

## `lib/screens/speak/v3_settings_screen.dart`
- widgets: V3SettingsScreen
- opens: PrivacyAiScreen, SpeakPaywallScreen
- tap handlers: 10
- labels: 'A1', 'A2', 'B1', 'B2', 'Deep', 'Everyday French', 'Explore first', 'Quick', 'Standard', 'TEF Canada'

## `lib/screens/subscription/speak_paywall_screen.dart`
- widgets: SpeakPaywallScreen
- tap handlers: 6
- labels: 'BEST VALUE'

## `lib/widgets/adaptive/adaptive.dart`
- widgets: PSSwitch, PSProgressIndicator, PSContentColumn, PSBottomActionBar
- tap handlers: 10

## `lib/widgets/auth_form.dart`
- widgets: AuthForm
- tap handlers: 6
- labels: 'Create account', 'Sign in'

## `lib/widgets/bilingual_word_text.dart`
- widgets: BilingualWordText
- tap handlers: 1

## `lib/widgets/error_notice.dart`
- widgets: ErrorNotice
- tap handlers: 1

## `lib/widgets/floating_notetaker.dart`
- widgets: FloatingNotetakerOverlay
- tap handlers: 5
- labels: 'Keep note for later'

## `lib/widgets/grammar_live_audio_button.dart`
- widgets: GrammarLiveAudioButton
- tap handlers: 1

## `lib/widgets/inline_call_bar.dart`
- widgets: InlineCallActions, _CallActionButton, InlineCallStatusCard, InlineTutorConnectionCard
- tap handlers: 4

## `lib/widgets/kicker_text.dart`
- widgets: KickerText
- tap handlers: 0

## `lib/widgets/learning_card.dart`
- widgets: LearningCard
- tap handlers: 1

## `lib/widgets/lesson_qa_overlay.dart`
- widgets: LessonQAOverlay
- tap handlers: 3
- labels: 'Close', 'Replay answer'

## `lib/widgets/lesson_stage_rail.dart`
- widgets: LessonStageRail
- tap handlers: 1

## `lib/widgets/live_tutor_mascot.dart`
- widgets: LiveTutorMascot
- tap handlers: 0

## `lib/widgets/mic_mode_bar.dart`
- widgets: MicModeBar, MicPrimaryButton
- tap handlers: 6
- labels: 'Auto', 'Hold'

## `lib/widgets/passeport_card.dart`
- widgets: PasseportCard
- tap handlers: 0

## `lib/widgets/passeport_primary_button.dart`
- widgets: PasseportPrimaryButton
- tap handlers: 2

## `lib/widgets/personalized_generation_loader.dart`
- widgets: PersonalizedGenerationLoader, _GenerationMark
- tap handlers: 0

## `lib/widgets/practice_content_card.dart`
- widgets: PracticeContentCard, _PracticeArtwork
- tap handlers: 1

## `lib/widgets/primary_action_button.dart`
- widgets: PrimaryActionButton
- tap handlers: 1

## `lib/widgets/progress_ring.dart`
- widgets: SpinningRing
- tap handlers: 0

## `lib/widgets/report_problem_button.dart`
- widgets: ReportProblemButton
- tap handlers: 1
- labels: 'Report a problem'

## `lib/widgets/responsive_card_grid.dart`
- widgets: ResponsiveCardGrid
- tap handlers: 0

## `lib/widgets/session_row.dart`
- widgets: SessionRow
- tap handlers: 0

## `lib/widgets/speaking_murray_bar.dart`
- widgets: SpeakingMurrayBar
- tap handlers: 1

## `lib/widgets/speaking_session_result.dart`
- widgets: SpeakingSessionResultView, _ResultMetric
- tap handlers: 2
- labels: 'Close result', 'connected', 'transcript'

## `lib/widgets/speaking_transcript_strip.dart`
- widgets: SpeakingTranscriptStrip, _TranscriptLine
- tap handlers: 0

## `lib/widgets/story_cover_image.dart`
- widgets: StoryCoverImage
- tap handlers: 0

## `lib/widgets/subscription_marketing_sections.dart`
- widgets: SubscriptionMarketingSections, _LearningRouteCard, _LevelTag, _PersonalizationComparisonCard, _ComparisonColumn, _ContextLearningCard, _MiniTag, _ContextFeature, SubscriptionBottomOffer
- tap handlers: 1

## `lib/widgets/tts_play_button.dart`
- widgets: TtsPlayButton
- tap handlers: 2

## `lib/widgets/tutor_avatar_stage.dart`
- widgets: TutorAvatarStage, _PortraitFallback
- tap handlers: 0

## `lib/widgets/tutor_helper_settings_panel.dart`
- widgets: TutorHelperSettingsPanel
- tap handlers: 1

## `lib/widgets/tutor_storyboard_avatar_stage.dart`
- widgets: TutorStoryboardAvatarStage, _FrameImage
- tap handlers: 0
- keys: `tutor-storyboard-$displayedFrame`

## `lib/widgets/v3/v3_surface.dart`
- widgets: V3Scaffold, V3Header, V3BackButton, V3IconButton, V3SectionLabel, V3Card, V3Row, V3PrimaryButton, V3Toggle, V3EmptyState
- tap handlers: 7
- labels: 'Back'

## `lib/widgets/web/web_app_shell.dart`
- widgets: WebAppShell, _Sidebar, _BrandHeader, _GroupLabel, _NavRow, _TopBar, WebIconButton
- tap handlers: 3

## `lib/widgets/web/web_auth_layout.dart`
- widgets: WebAuthLayout, WebAuthFrame, _BrandPanel, _RouteRow
- tap handlers: 0

## `lib/widgets/web/web_call_layout.dart`
- widgets: WebCallLayout, _TopBar, _StatusChip, _TutorRail, _ErrorBanner
- tap handlers: 1
- labels: 'End practice'

## `lib/widgets/web/web_constrained_view.dart`
- widgets: WebConstrainedView
- tap handlers: 0

## `lib/widgets/web/web_layout.dart`
- widgets: WebPage, WebPageHeader, WebSectionHeader, WebTextAction, WebCard, WebCardGrid, WebChip
- tap handlers: 3

## `lib/widgets/web/web_lesson_layout.dart`
- widgets: WebLessonLayout, _TopBar, _StatusChip
- tap handlers: 1
- labels: 'End practice'

## `lib/widgets/web/web_lesson_rail.dart`
- widgets: WebLessonProgressRail, _CompactProgress, _RailCard, _RouteStep
- tap handlers: 0

## `lib/widgets/web/web_onboarding_question.dart`
- widgets: WebOnboardingQuestion, _RouteRow
- tap handlers: 0

## `lib/widgets/web/web_onboarding_welcome.dart`
- widgets: WebOnboardingWelcome, _RouteRow
- tap handlers: 1

## `lib/widgets/web/web_practice_grid.dart`
- widgets: WebPracticeGrid
- tap handlers: 1

## `lib/widgets/web/web_preparing_pane.dart`
- widgets: WebPreparingPane
- tap handlers: 0

## `lib/widgets/word_conjugation_sheet.dart`
- widgets: WordConjugationSheet
- tap handlers: 1

## `lib/widgets/word_meaning_overlay.dart`
- widgets: WordMeaningOverlay
- tap handlers: 1

