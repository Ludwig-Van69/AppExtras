import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/device_store.dart';
import '../data/app_database.dart';
import '../data/app_settings.dart';
import '../data/company_repository.dart';
import '../data/day_entry_repository.dart';
import '../data/extras_repository.dart';
import '../data/folder_storage.dart';
import '../data/holiday_store.dart';
import '../data/money_repository.dart';
import '../data/prefs_store.dart';
import '../data/saved_hours_repository.dart';
import '../data/vacation_repository.dart';
import '../data/first_steps_store.dart';
import '../data/pre_migration_backup.dart';
import 'extras/extras_controller.dart';
import 'first_steps/first_steps_controller.dart';
import 'holidays/holidays_controller.dart';
import 'money/money_controller.dart';
import 'backup/backup_controller.dart';
import 'company/company_controller.dart';
import 'home_shell.dart';
import 'theme/app_theme.dart';
import 'theme/decor_colors.dart';
import 'theme/tokens.dart';
import 'vacation/vacation_controller.dart';

/// Raíz de la app: aplica el tema y la elección claro u oscuro.
class HoursAndVacationApp extends StatefulWidget {
  const HoursAndVacationApp({
    super.key,
    this.home,
    this.repository,
    this.clock,
    this.backup,
    this.holidays,
    this.money,
    this.extras,
    this.prefs,
    this.vacation,
    this.firstSteps,
    this.company,
  });

  /// La tarjeta «Primeros pasos» (024). Si no se indica y se usa la base de
  /// datos real, la de verdad; con un repositorio de prueba, sin tarjeta.
  final FirstStepsController? firstSteps;

  /// La empresa (026), igual que [money].
  final CompanyController? company;

  /// Las vacaciones, igual que [money].
  final VacationController? vacation;

  /// Dónde se recuerda el tema elegido (009, RF-10). Si no se indica y se usa
  /// la base de datos real, el archivo de preferencias del móvil; con un
  /// repositorio de prueba, el tema no se recuerda.
  final PrefsStore? prefs;

  /// Pantalla inicial; si no se indica, la de apuntar horas (RF-1).
  final Widget? home;

  /// Dónde se guardan los días; si no se indica, la base de datos del móvil.
  final DayEntryRepository? repository;

  /// Reloj para los tests; si es nulo, la hora real.
  final DateTime Function()? clock;

  /// Las copias. Si no se indica y se usa la base de datos real, se crean las
  /// de verdad; con un repositorio de prueba, la app va sin copias.
  final BackupService? backup;

  /// Los festivos. Si no se indica y se usa la base de datos real, se crean
  /// los de verdad; con un repositorio de prueba, solo fines de semana.
  final HolidaysController? holidays;

  /// El dinero. Si no se indica y se usa la base de datos real, se crea el de
  /// verdad; con un repositorio de prueba, la app va sin sección Dinero.
  final MoneyController? money;

  /// Las multas y extras, igual que [money].
  final ExtrasController? extras;

  @override
  State<HoursAndVacationApp> createState() => _HoursAndVacationAppState();
}

class _HoursAndVacationAppState extends State<HoursAndVacationApp>
    with WidgetsBindingObserver {
  final _theme = ThemeController();
  final _decor = CalendarDecorController();
  late final DayEntryRepository _repository =
      widget.repository ??
      SqliteDayEntryRepository(
        () => openAppDatabase(
          backupBeforeUpgrade: (path) => backupBeforeUpgrade(
            path,
            storage: ChannelFolderStorage(),
            settings: SettingsStore.inAppFolder(),
            device: DeviceStore.inAppFolder(),
          ),
        ),
      );
  late final BackupService? _backup = widget.backup ?? _realBackup();
  late final MoneyController? _money = widget.money ?? _realMoney();
  late final ExtrasController? _extras = widget.extras ?? _realExtras();
  late final VacationController? _vacation = widget.vacation ?? _realVacation();

  late final CompanyController? _company = widget.company ?? _realCompany();

  CompanyController? _realCompany() {
    final repo = _repository;
    if (widget.repository != null || repo is! SqliteDayEntryRepository) {
      return null;
    }
    return CompanyController(
      repository: SqliteCompanyRepository(() => repo.database),
      clock: widget.clock,
      onChanged: () async => _backup?.markChanged(),
    )..load();
  }

  VacationController? _realVacation() {
    final repo = _repository;
    if (widget.repository != null || repo is! SqliteDayEntryRepository) {
      return null;
    }
    return VacationController(
      repository: SqliteVacationRepository(() => repo.database),
      clock: widget.clock,
      onChanged: () async => _backup?.markChanged(),
      calendar: _holidays == null ? null : () => _holidays.calendar,
    )..load();
  }

  ExtrasController? _realExtras() {
    final repo = _repository;
    if (widget.repository != null || repo is! SqliteDayEntryRepository) {
      return null;
    }
    return ExtrasController(
      repository: SqliteExtrasRepository(() => repo.database),
      clock: widget.clock,
      onChanged: () async => _backup?.markChanged(),
    )..load();
  }

  MoneyController? _realMoney() {
    final repo = _repository;
    if (widget.repository != null || repo is! SqliteDayEntryRepository) {
      return null;
    }
    final prefs = PrefsStore.inAppFolder();
    return MoneyController(
      days: repo,
      money: SqliteMoneyRepository(() => repo.database),
      saved: SqliteSavedHoursRepository(() => repo.database),
      clock: widget.clock,
      loadHidden: prefs.loadHideAmounts,
      saveHidden: prefs.saveHideAmounts,
      onChanged: () async => _backup?.markChanged(),
    )..load();
  }

  late final HolidaysController? _holidays =
      widget.holidays ??
      (widget.repository == null
          ? (HolidaysController.withStore(HolidayStore.inAppFolder())..load())
          : null);

  BackupService? _realBackup() {
    final repo = _repository;
    if (widget.repository != null || repo is! SqliteDayEntryRepository) {
      return null;
    }
    return BackupController(
      openDatabase: () => repo.database,
      settingsStore: SettingsStore.inAppFolder(),
      storage: ChannelFolderStorage(),
      deviceStore: DeviceStore.inAppFolder(),
    )..load();
  }

  late final FirstStepsController? _firstSteps =
      widget.firstSteps ??
      (widget.repository == null
          ? (FirstStepsController.withStore(FirstStepsStore.inAppFolder())
              ..load())
          : null);

  late final PrefsStore? _prefs =
      widget.prefs ??
      (widget.repository == null ? PrefsStore.inAppFolder() : null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _holidays?.addListener(_holidaysChanged);
    _loadTheme();
  }

  /// Lee el tema guardado y, desde entonces, guarda cada cambio (009,
  /// RF-10). Si no se puede leer, se queda en Automático.
  Future<void> _loadTheme() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final saved = await prefs.loadTheme();
      final choice = ThemeChoice.values.asNameMap()[saved];
      if (choice != null && mounted) _theme.value = choice;
    } catch (_) {
      // Vale Automático.
    }
    _theme.addListener(_saveTheme);
    try {
      final decor = await prefs.loadCalendarDecor();
      if (mounted) _decor.value = decor;
    } catch (_) {
      // Activados.
    }
    _decor.addListener(_saveDecor);
  }

  void _holidaysChanged() => _vacation?.calendarChanged();

  Future<void> _saveDecor() async {
    try {
      await _prefs?.saveCalendarDecor(_decor.value);
    } catch (_) {
      // Vale hasta cerrar la app.
    }
  }

  Future<void> _saveTheme() async {
    try {
      await _prefs?.saveTheme(_theme.value.name);
    } catch (_) {
      // El tema vale hasta cerrar la app.
    }
  }

  /// Si el usuario cambia el ajuste de animaciones con la app abierta, el
  /// cambio de tema lo respeta al momento (RF-10).
  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holidays?.removeListener(_holidaysChanged);
    _theme.dispose();
    _decor.dispose();
    super.dispose();
  }

  bool get _animationsOff => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: _theme,
      child: CalendarDecorScope(
        controller: _decor,
        child: ValueListenableBuilder<ThemeChoice>(
          valueListenable: _theme,
          builder: (context, choice, _) => MaterialApp(
            title: 'Extras',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: choice.mode,
            themeAnimationDuration: _animationsOff
                ? Duration.zero
                : Motion.theme,
            // Calendario y textos del sistema en castellano.
            locale: const Locale('es', 'ES'),
            supportedLocales: const [Locale('es', 'ES')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home:
                widget.home ??
                HomeShell(
                  repository: _repository,
                  clock: widget.clock,
                  backup: _backup,
                  holidays: _holidays,
                  money: _money,
                  extras: _extras,
                  vacation: _vacation,
                  firstSteps: _firstSteps,
                  company: _company,
                ),
          ),
        ),
      ),
    );
  }
}
