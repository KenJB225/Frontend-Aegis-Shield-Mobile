import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const AegisDryApp());
}

class AegisDryApp extends StatelessWidget {
  const AegisDryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aegis-Dry',
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final width = media.size.width;
        final textScale = (width / 390).clamp(0.74, 1.0);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.surface,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 42, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class AppColors {
  static const Color primary = Color(0xFF169A92);
  static const Color primaryDark = Color(0xFF107F79);
  static const Color accentBlue = Color(0xFF2F62DE);
  static const Color danger = Color(0xFFE9232B);
  static const Color textMain = Color(0xFF1B2236);
  static const Color textMuted = Color(0xFF7B89A5);
  static const Color surface = Color(0xFFF3F6FA);
  static const Color card = Colors.white;
  static const Color line = Color(0xFFD8E0EB);
  static const Color success = Color(0xFF22B573);
}

double responsiveScale(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return (width / 390).clamp(0.78, 1.0);
}

double rs(BuildContext context, double size, {double min = 12}) {
  return math.max(min, size * responsiveScale(context));
}

class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxWidth = width > 460 ? 440.0 : width;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: maxWidth, child: child),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Timer _timer;
  double _progress = 0.35;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 380), (timer) {
      if (!mounted) {
        return;
      }
      setState(() {
        _progress += 0.09;
      });
      if (_progress >= 1) {
        timer.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int percent = (_progress.clamp(0, 1) * 100).toInt();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7FBFD), Color(0xFFEEF4F8)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD7E0EA)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 28),
                const Text.rich(
                  TextSpan(
                    text: 'Aegis-Dry ',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                    children: [
                      TextSpan(
                        text: 'Smart Dock',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Smart Protection for Your\nLaundry',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: AppColors.textMuted),
                ),
                const SizedBox(height: 64),
                Row(
                  children: [
                    const Text(
                      'INITIALIZING SYSTEM',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Color(0xFF6E7F9F),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress.clamp(0, 1),
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: const Color(0xFFD8E0EC),
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _PillTag(label: 'SENSORS ONLINE'),
                    SizedBox(width: 8),
                    _PillTag(label: 'CLOUD LINKED'),
                  ],
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'VERSION 2.4.0  •  SECURED BY AEGIS',
                    style: TextStyle(
                      color: Color(0xFF8C9AB2),
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillTag extends StatelessWidget {
  const _PillTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E1EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: Color(0xFF62748F),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _validUsername = 'admin';
  static const String _validPassword = 'admin123';

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 40, min: 30);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7FBFD), Color(0xFFEDF5F8)],
          ),
        ),
        child: AppViewport(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE3EAF2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFD),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE1E8F1)),
                          ),
                          child: const Icon(
                            Icons.shield,
                            size: 44,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Aegis-Dry',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Center(
                        child: Text(
                          'Smart Protection for Your Laundry',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Username',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildInput(
                        controller: _usernameController,
                        hint: 'admin',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text(
                            'Password',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMain,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildInput(
                        controller: _passwordController,
                        hint: 'Enter password',
                        icon: Icons.lock_outline,
                        obscure: _obscurePassword,
                        suffix: IconButton(
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 18,
                            color: const Color(0xFF8C9BB2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (value) {
                              setState(() => _rememberMe = value ?? false);
                            },
                            side: const BorderSide(color: Color(0xFFD4DDE9)),
                          ),
                          const Text(
                            'Remember me',
                            style: TextStyle(color: Color(0xFF6F8099)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _onLogin,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Login',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('New to Aegis-Dry? ', style: TextStyle(color: Color(0xFF8A98AE))),
                          Text(
                            'Create an account',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFFE5ECF3)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9AA8BC)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF97A7BE)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF6F9FC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDBE3EE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDBE3EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }

  void _onLogin() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username == _validUsername && password == _validPassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigationShell()),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invalid credentials. Try admin / admin123.')),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onOpenManualControl: _openManualControl,
        onOpenDashboard: () => setState(() => _index = 1),
      ),
      DashboardScreen(onOpenHistory: _openActivityHistory),
      DeviceScreen(onOpenManualControl: _openLiveConsoleManual),
      const AlertsScreen(),
      SettingsScreen(onOpenThreshold: _openThresholdConfig),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        height: 74,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: Colors.white,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'HOME',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'DASHBOARD',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory),
            label: 'DEVICE',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'ALERTS',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'SETTINGS',
          ),
        ],
      ),
    );
  }

  void _openManualControl() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManualOverrideScreen()));
  }

  void _openLiveConsoleManual() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManualOverrideLiveScreen()));
  }

  void _openActivityHistory() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ActivityHistoryScreen()));
  }

  void _openThresholdConfig() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ThresholdConfigurationScreen()),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenDashboard,
    required this.onOpenManualControl,
  });

  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenManualControl;

  @override
  Widget build(BuildContext context) {
    final headline = rs(context, 31, min: 24);
    final greeting = rs(context, 48, min: 34);
    final sectionTitle = rs(context, 32, min: 24);
    final buttonText = rs(context, 26, min: 20);
    final secondaryButtonText = rs(context, 24, min: 18);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(
                    0xFF1B9890,
                  ).withValues(alpha: 0.24),
                  child: const Icon(Icons.person, color: AppColors.textMain),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aegis-Dry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: headline,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0F6),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.notifications_none,
                    color: AppColors.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Welcome back,',
              style: TextStyle(fontSize: 18, color: Color(0xFF77859E)),
            ),
            Text(
              'Hello, User',
              style: TextStyle(
                fontSize: greeting,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusCard(context),
            const SizedBox(height: 14),
            Row(
              children: const [
                Expanded(
                  child: _MetricCard(
                    title: 'TEMP',
                    value: '72°F',
                    subtitle: 'Indoor average',
                    icon: Icons.thermostat_outlined,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: 'SKY',
                    value: 'Clear',
                    subtitle: 'Local forecast',
                    icon: Icons.cloud_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onOpenDashboard,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.grid_view_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Open Dashboard',
                    style: TextStyle(
                      fontSize: buttonText,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD2DBE8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: onOpenManualControl,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.textMain),
                  const SizedBox(width: 8),
                  Text(
                    'Manual Control',
                    style: TextStyle(
                      fontSize: secondaryButtonText,
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Quick Stats',
              style: TextStyle(
                fontSize: sectionTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 10),
            const _StatTile(
              icon: Icons.water_drop_outlined,
              label: 'Humidity',
              value: '45%',
            ),
            const SizedBox(height: 8),
            const _StatTile(
              icon: Icons.air,
              label: 'Air Quality',
              value: 'Excellent',
              valueColor: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final safeText = rs(context, 52, min: 36);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FFFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFE8DA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'SYSTEM STATUS',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDCF6EA),
                  border: Border.all(color: const Color(0xFF88DBC0)),
                ),
                child: const Icon(Icons.check, color: AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Safe',
            style: TextStyle(
              fontSize: safeText,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          const Text(
            'All sensors are operating normally.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 17),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  child: LinearProgressIndicator(
                    value: 1,
                    minHeight: 6,
                    color: AppColors.success,
                    backgroundColor: Color(0xFFCAE7D7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '100% Secure',
                style: TextStyle(
                  color: AppColors.success.withValues(alpha: 0.96),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenHistory});

  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final header = rs(context, 32, min: 24);
    final statusHeadline = rs(context, 44, min: 30);
    final sectionHeader = rs(context, 24, min: 18);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          children: [
            Row(
              children: [
                const Icon(Icons.menu, color: AppColors.textMain),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aegis-Dry System',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: header,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6ECF4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.account_circle_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFC7EBE6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF79CBC1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SYSTEM STATUS',
                    style: TextStyle(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Monitoring - Safe',
                    style: TextStyle(
                      fontSize: statusHeadline,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Last checked: 2 minutes ago',
                    style: TextStyle(fontSize: 20, color: Color(0xFF536579)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ENVIRONMENTAL METRICS',
              style: TextStyle(
                letterSpacing: 2,
                fontSize: sectionHeader,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5B667A),
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: '',
                    value: '24°C',
                    subtitle: 'Temp',
                    icon: Icons.thermostat,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: '',
                    value: '45%',
                    subtitle: 'Humidity',
                    icon: Icons.water_drop,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: '',
                    value: '10%',
                    subtitle: 'Rain',
                    icon: Icons.grain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'ACTIVITY LOG',
                  style: TextStyle(
                    letterSpacing: 2,
                    fontSize: sectionHeader,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5B667A),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onOpenHistory,
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const _ActivityTile(
              icon: Icons.check_circle_outline,
              title: 'System Self-Test',
              subtitle: 'All modules operating normally',
              time: '10:45 AM',
            ),
            const SizedBox(height: 8),
            const _ActivityTile(
              icon: Icons.network_ping,
              title: 'Sensor Sync',
              subtitle: 'Updated humidity thresholds',
              time: '09:12 AM',
            ),
            const SizedBox(height: 8),
            const _ActivityTile(
              icon: Icons.restore,
              title: 'Routine Backup',
              subtitle: 'Data synced to cloud',
              time: 'Yesterday',
              isMuted: true,
            ),
          ],
        ),
      ),
    );
  }
}

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.onOpenManualControl});

  final VoidCallback onOpenManualControl;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 37, min: 28);
    final networkStateSize = rs(context, 48, min: 34);
    final sensorsTitle = rs(context, 36, min: 26);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aegis-Dry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onOpenManualControl,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9EFF5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1E7F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NETWORK STATUS',
                    style: TextStyle(
                      letterSpacing: 2,
                      color: Color(0xFF6892A0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Online',
                    style: TextStyle(
                      fontSize: networkStateSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '4 Sensors connected & active',
                    style: TextStyle(fontSize: 19, color: Color(0xFF667E98)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Active Sensors',
                    style: TextStyle(
                      fontSize: sensorsTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'LAST SYNC: JUST NOW',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    style: TextStyle(
                      letterSpacing: 1.4,
                      color: Color(0xFF7A89A2),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _SensorTile(
              name: 'Rain Sensor',
              status: 'Online',
              reading: '0% Dry',
              time: '2 mins ago',
              icon: Icons.water_drop_outlined,
            ),
            const SizedBox(height: 10),
            const _SensorTile(
              name: 'Temperature Sensor',
              status: 'Online',
              reading: '24°C',
              time: '5 mins ago',
              icon: Icons.thermostat,
            ),
            const SizedBox(height: 10),
            const _SensorTile(
              name: 'Humidity Sensor',
              status: 'Online',
              reading: '45% RH',
              time: '1 min ago',
              icon: Icons.eco_outlined,
            ),
            const SizedBox(height: 10),
            const _SensorTile(
              name: 'Soil Moisture',
              status: 'Offline',
              reading: 'Link Lost',
              time: '2 hours ago',
              icon: Icons.grass,
              isOffline: true,
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Expanded(
                  child: _InfoStatCard(
                    title: 'Avg. Battery',
                    value: '82%',
                    icon: Icons.battery_5_bar,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _InfoStatCard(
                    title: 'Signal Strength',
                    value: 'Excellent',
                    icon: Icons.signal_cellular_alt,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 43, min: 30);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          children: [
            Row(
              children: [
                const Icon(Icons.arrow_back),
                const SizedBox(width: 10),
                Text(
                  'Alerts',
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.done_all, color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'TODAY',
              style: TextStyle(
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: Color(0xFF66758F),
              ),
            ),
            const SizedBox(height: 10),
            const _AlertTile(
              icon: Icons.cloudy_snowing,
              iconColor: Color(0xFFE84E47),
              title: 'Rain detected - rack\nautomatically retracted',
              body:
                  'Sensors detected precipitation above\n2mm. Aegis-Dry system secured your\nlaundry.',
              time: '10:32 AM',
              rightLabel: 'JUST\nNOW',
            ),
            const SizedBox(height: 10),
            const _AlertTile(
              icon: Icons.check_circle,
              iconColor: Color(0xFF2BB87E),
              title: 'Rack successfully extended',
              body:
                  'Manual command completed. Your\nrack is now fully deployed for drying.',
              time: '08:15 AM',
              rightLabel: '2H AGO',
            ),
            const SizedBox(height: 12),
            const Text(
              'YESTERDAY',
              style: TextStyle(
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: Color(0xFF66758F),
              ),
            ),
            const SizedBox(height: 10),
            const _AlertTile(
              icon: Icons.warning_amber_rounded,
              iconColor: Color(0xFFF0A63B),
              title: 'High rain probability detected\n(80%)',
              body:
                  'Weather forecast indicates likely rain\nwithin the next 30 minutes. Consider\nretracting.',
              time: '04:45 PM',
            ),
            const SizedBox(height: 10),
            const _AlertTile(
              icon: Icons.sync,
              iconColor: AppColors.primary,
              title: 'System Firmware Updated',
              body:
                  'Aegis-Dry v2.4.0 was installed\nsuccessfully. New rain prediction\nalgorithms active.',
              time: '11:20 AM',
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onOpenThreshold});

  final VoidCallback onOpenThreshold;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool darkMode = false;
  bool pushNotifications = true;
  bool emailAlerts = false;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 30, min: 22);
    final brandSize = rs(context, 44, min: 30);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.arrow_back),
                  const Spacer(),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDDF4EF),
                  border: Border.all(color: const Color(0xFF8ADACA)),
                ),
                child: const Icon(
                  Icons.shield,
                  color: AppColors.primary,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Aegis-Dry',
                style: TextStyle(
                  fontSize: brandSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
            ),
            const Center(
              child: Text(
                'Industrial Humidity Control',
                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
            ),
            const SizedBox(height: 14),
            const _SectionLabel(label: 'PREFERENCES'),
            _SwitchTile(
              icon: Icons.dark_mode_outlined,
              title: 'Dark Mode',
              subtitle: 'Switch between light and dark\nthemes',
              value: darkMode,
              onChanged: (value) => setState(() => darkMode = value),
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'Notifications'),
            _SwitchTile(
              icon: Icons.notifications_none,
              title: 'Push Notifications',
              value: pushNotifications,
              onChanged: (value) => setState(() => pushNotifications = value),
            ),
            _SwitchTile(
              icon: Icons.mail_outline,
              title: 'Email Alerts',
              value: emailAlerts,
              onChanged: (value) => setState(() => emailAlerts = value),
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'DEVICE CALIBRATION'),
            const _ChevronTile(
              title: 'Sensor Calibration',
              subtitle: 'Adjust humidity and temp offsets',
              icon: Icons.tune,
            ),
            GestureDetector(
              onTap: widget.onOpenThreshold,
              child: const _ChevronTile(
                title: 'Threshold Configuration',
                subtitle: 'Set alert limits for all devices',
                icon: Icons.tune_outlined,
              ),
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'APPLICATION INFO'),
            const _SimpleInfoTile(
              title: 'App Version',
              trailing: 'v2.4.1 (Stable)',
            ),
            const _SimpleInfoTile(
              title: 'About Aegis-Dry',
              trailingIcon: Icons.info_outline,
            ),
            const _SimpleInfoTile(
              title: 'Sign Out',
              titleColor: Color(0xFFE33131),
              trailingIcon: Icons.logout,
              trailingColor: Color(0xFFE33131),
            ),
          ],
        ),
      ),
    );
  }
}

class ThresholdConfigurationScreen extends StatefulWidget {
  const ThresholdConfigurationScreen({super.key});

  @override
  State<ThresholdConfigurationScreen> createState() =>
      _ThresholdConfigurationScreenState();
}

class _ThresholdConfigurationScreenState
    extends State<ThresholdConfigurationScreen> {
  double value = 75;

  @override
  Widget build(BuildContext context) {
    final title = rs(context, 42, min: 30);
    final thresholdLabel = rs(context, 28, min: 20);
    final thresholdValue = rs(context, 40, min: 28);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          'Threshold Configuration',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.info_outline, color: AppColors.primary),
          ),
        ],
      ),
      body: AppViewport(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            children: [
              Row(
                children: [
                  const Icon(Icons.eco, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aegis-Dry Settings',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: title,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Set the rain probability at which the laundry\nrack should automatically retract to protect\nyour clothes.',
                style: TextStyle(fontSize: 18, color: Color(0xFF60728F)),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE5EF)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rain Probability Threshold',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: thresholdLabel,
                              color: Color(0xFF3F4F66),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${value.round()}%',
                          style: TextStyle(
                            fontSize: thresholdValue,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: const Color(0xFFD8E0EC),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: value,
                        min: 0,
                        max: 100,
                        onChanged: (v) => setState(() => value = v),
                      ),
                    ),
                    const Row(
                      children: [
                        Text(
                          '0% (LOW)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6F7F98),
                          ),
                        ),
                        Spacer(),
                        Text(
                          '50%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6F7F98),
                          ),
                        ),
                        Spacer(),
                        Text(
                          '100% (HIGH)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6F7F98),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F8F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFEDE2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: AppColors.primary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Local Forecast',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            'Rain probability for the next 2 hours is\n12%.',
                            style: TextStyle(color: Color(0xFF4F5F76)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Threshold saved at ${value.round()}%'),
                    ),
                  );
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Save Settings',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
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

class ManualOverrideScreen extends StatelessWidget {
  const ManualOverrideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final emergencyText = rs(context, 30, min: 22);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          'Manual Override',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.info_outline),
          ),
        ],
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE3E8F1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error, color: Color(0xFFFF6B57), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SYSTEM MOVING...',
                          style: TextStyle(
                            color: Color(0xFFFF6B57),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'Rack is currently transitioning to extended\nposition.',
                          style: TextStyle(color: Color(0xFFFF6B57)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '45%',
                    style: TextStyle(
                      color: Color(0xFF70809A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCE4EF)),
              ),
              child: Center(
                child: Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 7),
                  ),
                  child: const Center(
                    child: Text(
                      'Retracted',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'Extend Rack',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentBlue,
                      minimumSize: const Size.fromHeight(70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'Retract Rack',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE4EF)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SAFETY PROTOCOLS',
                    style: TextStyle(
                      letterSpacing: 2,
                      color: Color(0xFF95A3BC),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 10),
                  _SafetyRow(text: 'Clear area of obstacles'),
                  SizedBox(height: 8),
                  _SafetyRow(text: 'Verify weight limit (< 25kg)'),
                  SizedBox(height: 8),
                  _SafetyRow(text: 'Stable power connection'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {},
              child: Text(
                'EMERGENCY STOP',
                style: TextStyle(
                  fontSize: emergencyText,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ManualOverrideLiveScreen extends StatelessWidget {
  const ManualOverrideLiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rackValue = rs(context, 42, min: 30);
    final emergencyText = rs(context, 32, min: 22);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual Override',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            Text(
              'AEGIS-DRY SYSTEM',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Chip(label: Text('Live Console')),
          ),
        ],
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE6F1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RACK POSITION STATUS',
                    style: TextStyle(
                      letterSpacing: 2,
                      color: Color(0xFF687991),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '50% Extended',
                    style: TextStyle(
                      fontSize: rackValue,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    child: LinearProgressIndicator(
                      value: 0.5,
                      minHeight: 12,
                      color: AppColors.primary,
                      backgroundColor: Color(0xFFE6ECF5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'RETRACTED PARTIAL (OPTIMAL) FULLY EXTENDED',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7C8AA3),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE9F8F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBAE9DE)),
              ),
              child: const Text(
                'SAFETY PROTOCOL ACTIVE: HOLD BUTTON FOR 2 SECONDS TO INITIATE MOVEMENT. ANY MOVEMENT WILL TRIGGER THE EXTERNAL STROBE LIGHT.',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Color(0xFF638099),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ConsoleActionButton(
                    title: 'EXTEND RACK',
                    icon: Icons.unfold_more,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ConsoleActionButton(
                    title: 'RETRACT RACK',
                    icon: Icons.unfold_less,
                    darkIcon: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {},
              child: Text(
                'EMERGENCY STOP',
                style: TextStyle(
                  fontSize: emergencyText,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'DISENGAGES ALL HYDRAULIC POWER IMMEDIATELY',
                style: TextStyle(
                  letterSpacing: 2,
                  color: Color(0xFF9CA8BC),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aegis-Dry',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            Text(
              'Activity History Logs',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.info_outline, color: AppColors.primary),
          ),
        ],
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search logs or events...',
                hintStyle: const TextStyle(color: Color(0xFF9AA9C0)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8FA0BA)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChipActive(label: 'All\nLogs'),
                  SizedBox(width: 8),
                  _FilterChipMute(label: 'Sensors'),
                  SizedBox(width: 8),
                  _FilterChipMute(label: 'System'),
                  SizedBox(width: 8),
                  _FilterChipMute(label: 'Manual'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'TODAY - OCT 24, 2023',
              style: TextStyle(
                color: Color(0xFF7588A4),
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const _TimelineItem(
              title: 'Rain sensor triggered',
              subtitle: 'Moisture levels exceeded 15% threshold.',
              time: '14:32 PM',
              response: 'Rack automatically retracted to Home\nposition.',
            ),
            const _TimelineItem(
              title: 'Manual override used',
              subtitle: "User 'Admin' initiated manual extension.",
              time: '12:15 PM',
              response: 'Auto-mode suspended for 60 minutes.',
              icon: Icons.pan_tool_alt_outlined,
            ),
            const _TimelineItem(
              title: 'Threshold updated',
              subtitle: 'Humidity sensitivity adjusted from 60% to\n55%.',
              time: '09:40 AM',
              response: 'New parameters synchronized to local\nhub.',
              icon: Icons.tune,
            ),
            const _TimelineItem(
              title: 'Rack automatically retracted',
              subtitle: 'Scheduled night-time retraction sequence.',
              time: '08:02 AM',
              response: 'Motors engaged. Position: 0% (Closed).',
              icon: Icons.precision_manufacturing_outlined,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final valueSize = rs(context, 24, min: 18);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E0EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.textMain,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final labelSize = rs(context, 22, min: 16);
    final valueSize = rs(context, 24, min: 17);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E2EE)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFA1B0C9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: labelSize, color: AppColors.textMain),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    this.isMuted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 24, min: 18);

    final Color titleColor = isMuted
        ? const Color(0xFF8F9BB1)
        : AppColors.textMain;
    final Color subtitleColor = isMuted
        ? const Color(0xFFAEB9CB)
        : AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E1EC)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isMuted
                ? const Color(0xFFF2F5FA)
                : const Color(0xFFE6F7F3),
            child: Icon(
              icon,
              color: isMuted ? const Color(0xFFA2B2C7) : AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                Text(subtitle, style: TextStyle(color: subtitleColor)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(color: Color(0xFF8C9DB5))),
        ],
      ),
    );
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.name,
    required this.status,
    required this.reading,
    required this.time,
    required this.icon,
    this.isOffline = false,
  });

  final String name;
  final String status;
  final String reading;
  final String time;
  final IconData icon;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 24, min: 18);
    final valueSize = rs(context, 24, min: 17);

    final Color dotColor = isOffline
        ? const Color(0xFFACB9CD)
        : const Color(0xFF2DB367);
    final Color readColor = isOffline
        ? const Color(0xFF9AA9BF)
        : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E1EC)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isOffline ? const Color(0xFFABB8CC) : AppColors.accentBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: const TextStyle(color: Color(0xFF7888A1)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: const TextStyle(color: Color(0xFF9BA8BE))),
              Text(
                reading,
                style: TextStyle(fontSize: valueSize, color: readColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoStatCard extends StatelessWidget {
  const _InfoStatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final valueSize = rs(context, 34, min: 24);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E1ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Color(0xFF667A98))),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              color: AppColors.textMain,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.time,
    this.rightLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String time;
  final String? rightLabel;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 24, min: 18);
    final bodySize = rs(context, 16, min: 13);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE4EF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: iconColor.withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: bodySize,
                    color: Color(0xFF61738D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(time, style: const TextStyle(color: Color(0xFF8C9BB2))),
              ],
            ),
          ),
          if (rightLabel != null)
            Text(
              rightLabel!,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFA8B4C8),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF7A8AA3)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, color: AppColors.textMain),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
        trailing: Switch(
          value: value,
          activeColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ChevronTile extends StatelessWidget {
  const _ChevronTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3E9F3))),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF7D8CA5)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, color: AppColors.textMain),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF90A0B8)),
      ),
    );
  }
}

class _SimpleInfoTile extends StatelessWidget {
  const _SimpleInfoTile({
    required this.title,
    this.trailing,
    this.trailingIcon,
    this.titleColor = AppColors.textMain,
    this.trailingColor = const Color(0xFF7E8EA7),
  });

  final String title;
  final String? trailing;
  final IconData? trailingIcon;
  final Color titleColor;
  final Color trailingColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3E9F2))),
      ),
      child: ListTile(
        title: Text(title, style: TextStyle(fontSize: 18, color: titleColor)),
        trailing: trailing != null
            ? Text(trailing!, style: TextStyle(color: trailingColor))
            : (trailingIcon != null
                  ? Icon(trailingIcon, color: trailingColor)
                  : null),
      ),
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 16, color: Color(0xFF6ACEA1)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 16, color: Color(0xFF566A86)),
        ),
      ],
    );
  }
}

class _ConsoleActionButton extends StatelessWidget {
  const _ConsoleActionButton({
    required this.title,
    required this.icon,
    this.darkIcon = false,
  });

  final String title;
  final IconData icon;
  final bool darkIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9E1EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFEAF3F2),
            child: Icon(
              icon,
              color: darkIcon ? const Color(0xFF70839F) : AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textMain,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipActive extends StatelessWidget {
  const _FilterChipActive({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FilterChipMute extends StatelessWidget {
  const _FilterChipMute({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E1EC)),
      ),
      child: Text(label, style: const TextStyle(color: Color(0xFF5E6F89))),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.response,
    this.icon = Icons.water_drop_outlined,
    this.isLast = false,
  });

  final String title;
  final String subtitle;
  final String time;
  final String response;
  final IconData icon;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: const Color(0xFFEAF0F7),
                  child: Icon(icon, size: 13, color: const Color(0xFF3E516B)),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.only(top: 4),
                      color: const Color(0xFFD3DDEB),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          color: AppColors.textMain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: const TextStyle(color: Color(0xFF8496B0)),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF60718A),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDCE4EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SYSTEM RESPONSE',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        response,
                        style: const TextStyle(color: Color(0xFF4B5D76)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
