import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const EthiopianEventsApp());
}

class EthiopianEventsApp extends StatelessWidget {
  const EthiopianEventsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ethiopian Events',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F5B)), useMaterial3: true),
    supportedLocales: const [Locale('en'), Locale('am')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const LoadingPage();
      if (snapshot.data == null) return const SignInPage();
      return const HomePage();
    },
  );
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}
class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false, busy = false;
  String? error;
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      if (register) {
        final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text);
        await result.user?.sendEmailVerification();
        if (mounted) setState(() => error = 'Account created. Check your email, then sign in. Ask an administrator to assign your role.');
        await FirebaseAuth.instance.signOut();
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? e.code);
    } catch (e) { setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.event_available, size: 64, color: Color(0xFF087F5B)),
        const SizedBox(height: 12), Text('Ethiopian Events', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('Plan celebrations. Welcome every guest.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : submit, child: busy ? const CircularProgressIndicator() : Text(register ? 'Create account' : 'Sign in')),
        TextButton(onPressed: busy ? null : () => setState(() { register = !register; error = null; }), child: Text(register ? 'Already registered? Sign in' : 'New here? Create account')),
        const Text('New accounts need an administrator to assign organizer or gate staff access.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
      ]),
    )))),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Ethiopian Events'), actions: [IconButton(tooltip: 'Sign out', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout))]),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.doc('users/$uid').snapshots(),
        builder: (context, userSnap) {
          if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());
          if (!userSnap.data!.exists) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Your account is signed in, but no app role is assigned yet. Ask the administrator to create users/$uid with role "organizer" or "gateStaff".')));
          final role = userSnap.data!.data()!['role'];
          if (role == 'organizer') return const OrganizerEventsPage();
          if (role == 'gateStaff') return const GateEventsPage();
          return const Center(child: Text('Access denied: unsupported account role.'));
        },
      ),
    );
  }
}

class OrganizerEventsPage extends StatelessWidget {
  const OrganizerEventsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final query = FirebaseFirestore.instance.collection('events').where('organizerUid', isEqualTo: uid).orderBy('dateTime');
    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: query.snapshots(), builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load events: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) return const Center(child: Text('No events yet. Create your first event.'));
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: snap.data!.docs.length, itemBuilder: (context, i) {
          final doc = snap.data!.docs[i], data = doc.data();
          return Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.celebration)),
            title: Text(data['title'] ?? 'Untitled event'),
            subtitle: Text('${data['venue'] ?? ''} • ${DateFormat.yMMMd().add_jm().format((data['dateTime'] as Timestamp).toDate())}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailPage(eventId: doc.id, data: data))),
          ));
        });
      }),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEventPage())), icon: const Icon(Icons.add), label: const Text('Create event')),
    );
  }
}

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key, this.eventId, this.initialData});
  final String? eventId;
  final Map<String, dynamic>? initialData;
  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}
class _CreateEventPageState extends State<CreateEventPage> {
  final title = TextEditingController(), description = TextEditingController(), venue = TextEditingController(), location = TextEditingController();
  DateTime dateTime = DateTime.now().add(const Duration(days: 7));
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null) {
      title.text = d['title'] ?? '';
      description.text = d['description'] ?? '';
      venue.text = d['venue'] ?? '';
      location.text = d['location'] ?? '';
      if (d['dateTime'] is Timestamp) dateTime = (d['dateTime'] as Timestamp).toDate();
    }
  }
  @override
  void dispose() { title.dispose(); description.dispose(); venue.dispose(); location.dispose(); super.dispose(); }
  Future<void> save() async {
    if (title.text.trim().isEmpty || venue.text.trim().isEmpty || location.text.trim().isEmpty || !dateTime.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter title, venue, location, and a future date/time.'))); return;
    }
    setState(() => busy = true);
    try {
      final eventData = {
        'title': title.text.trim(), 'description': description.text.trim(), 'venue': venue.text.trim(),
        'location': location.text.trim(), 'dateTime': Timestamp.fromDate(dateTime),
        'organizerUid': FirebaseAuth.instance.currentUser!.uid, 'attendanceCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (widget.eventId == null) {
        await FirebaseFirestore.instance.collection('events').add(eventData);
      } else {
        eventData.remove('createdAt');
        await FirebaseFirestore.instance.collection('events').doc(widget.eventId).update(eventData);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.eventId == null ? 'Create event' : 'Edit event')), body: ListView(padding: const EdgeInsets.all(16), children: [
    _field(title, 'Event title'), _field(description, 'Description', maxLines: 3), _field(venue, 'Venue name'), _field(location, 'Location / address'),
    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Date and time'), subtitle: Text(DateFormat.yMMMMd().add_jm().format(dateTime)), trailing: const Icon(Icons.calendar_month), onTap: () async {
      final d = await showDatePicker(context: context, initialDate: dateTime, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
      if (d == null || !mounted) return;
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dateTime));
      if (t != null) setState(() => dateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    }),
    const SizedBox(height: 12), FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Saving…' : (widget.eventId == null ? 'Save event' : 'Update event'))),
  ]));
}

Widget _field(TextEditingController c, String label, {int maxLines = 1}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.eventId, required this.data});
  final String eventId;
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final guests = FirebaseFirestore.instance.collection('events').doc(eventId).collection('guests');
    return Scaffold(appBar: AppBar(title: Text(data['title'] ?? 'Event'), actions: [
      IconButton(tooltip: 'Edit event', icon: const Icon(Icons.edit), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEventPage(eventId: eventId, initialData: data)))),
    ]), body: Column(children: [
      Card(margin: const EdgeInsets.all(12), child: ListTile(title: Text(data['venue'] ?? ''), subtitle: Text(data['location'] ?? ''), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${data['attendanceCount'] ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const Text('checked in')]))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        Expanded(child: Text('Guests', style: Theme.of(context).textTheme.titleLarge)),
        OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignStaffPage(eventId: eventId))), icon: const Icon(Icons.badge), label: const Text('Staff')),
        const SizedBox(width: 6),
        FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddGuestPage(eventId: eventId, eventTitle: data['title'] ?? 'Event'))), icon: const Icon(Icons.person_add), label: const Text('Add guest')),
      ])),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: guests.orderBy('createdAt', descending: true).snapshots(), builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Guest list unavailable: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) return const Center(child: Text('No guests invited yet.'));
        return ListView(children: snap.data!.docs.map((d) { final g = d.data(); return ListTile(leading: Icon(g['checkedIn'] == true ? Icons.check_circle : Icons.confirmation_number, color: g['checkedIn'] == true ? Colors.green : null), title: Text(g['name'] ?? 'Guest'), subtitle: Text(g['checkedIn'] == true ? 'Checked in' : (g['phone'] ?? g['email'] ?? 'Invited'))); }).toList());
      })),
    ]));
  }
}


class AssignStaffPage extends StatefulWidget {
  const AssignStaffPage({super.key, required this.eventId});
  final String eventId;
  @override
  State<AssignStaffPage> createState() => _AssignStaffPageState();
}
class _AssignStaffPageState extends State<AssignStaffPage> {
  final uidController = TextEditingController();
  bool busy = false;
  @override
  void dispose() { uidController.dispose(); super.dispose(); }
  Future<void> assign() async {
    if (uidController.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('assignGateStaff').call({
        'eventId': widget.eventId, 'staffUid': uidController.text.trim()
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gate staff assigned.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Assignment failed: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Assign gate staff')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Enter the Firebase Authentication UID of an account already assigned the gateStaff role.'),
      const SizedBox(height: 12),
      TextField(controller: uidController, decoration: const InputDecoration(labelText: 'Gate staff UID', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : assign, child: Text(busy ? 'Assigning…' : 'Assign to event')),
    ])),
  );
}

class AddGuestPage extends StatefulWidget {
  const AddGuestPage({super.key, required this.eventId, required this.eventTitle});
  final String eventId, eventTitle;
  @override
  State<AddGuestPage> createState() => _AddGuestPageState();
}
class _AddGuestPageState extends State<AddGuestPage> {
  final name = TextEditingController(), phone = TextEditingController(), email = TextEditingController();
  bool busy = false;
  @override
  void dispose() { name.dispose(); phone.dispose(); email.dispose(); super.dispose(); }
  String newCredential() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
  Future<void> create() async {
    if (name.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guest name is required.'))); return; }
    setState(() => busy = true);
    try {
      final credential = newCredential();
      final result = await FirebaseFunctions.instance.httpsCallable('createGuestTicket').call({
        'eventId': widget.eventId, 'name': name.text.trim(), 'phone': phone.text.trim(), 'email': email.text.trim(), 'credential': credential,
      });
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TicketPage(eventId: widget.eventId, eventTitle: widget.eventTitle, guestName: name.text.trim(), credential: credential)));
      debugPrint('Guest ticket created: ${result.data['guestId']}');
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create ticket: $e'))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Invite guest')), body: ListView(padding: const EdgeInsets.all(16), children: [
    _field(name, 'Guest full name'), _field(phone, 'Phone (optional)'), _field(email, 'Email (optional)'),
    const Text('A private QR credential will be generated. Guest details are not encoded in the QR.'), const SizedBox(height: 16),
    FilledButton(onPressed: busy ? null : create, child: Text(busy ? 'Creating…' : 'Create QR ticket')),
  ]));
}

class TicketPage extends StatelessWidget {
  const TicketPage({super.key, required this.eventId, required this.eventTitle, required this.guestName, required this.credential});
  final String eventId, eventTitle, guestName, credential;
  @override
  Widget build(BuildContext context) {
    final payload = jsonEncode({'v': 1, 'e': eventId, 'c': credential});
    return Scaffold(appBar: AppBar(title: const Text('Guest ticket')), body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
      Text(eventTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8), Text(guestName, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 24), QrImageView(data: payload, version: QrVersions.auto, size: 260, backgroundColor: Colors.white),
      const SizedBox(height: 12), const Text('Present this QR at the entrance. Keep it private.'),
      const SizedBox(height: 16), OutlinedButton.icon(onPressed: () => Share.share('My ticket for $eventTitle\nTicket data: $payload'), icon: const Icon(Icons.share), label: const Text('Share ticket')),
    ]))));
  }
}

class GateEventsPage extends StatelessWidget {
  const GateEventsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final query = FirebaseFirestore.instance.collectionGroup('staff').where('uid', isEqualTo: uid);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: query.snapshots(), builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Could not load assignments: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('No events assigned to you yet.'));
      return ListView(padding: const EdgeInsets.all(12), children: snap.data!.docs.map((staff) {
        final eventId = staff.reference.parent.parent!.id;
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(future: staff.reference.parent.parent!.get(), builder: (context, event) {
          if (!event.hasData || !event.data!.exists) return const SizedBox.shrink();
          final d = event.data!.data()!;
          return Card(child: ListTile(title: Text(d['title'] ?? 'Event'), subtitle: Text(d['venue'] ?? ''), trailing: const Icon(Icons.qr_code_scanner), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerPage(eventId: eventId, eventTitle: d['title'] ?? 'Event')))));
        });
      }).toList());
    });
  }
}


class ManualCheckInPage extends StatefulWidget {
  const ManualCheckInPage({super.key, required this.eventId});
  final String eventId;
  @override
  State<ManualCheckInPage> createState() => _ManualCheckInPageState();
}
class _ManualCheckInPageState extends State<ManualCheckInPage> {
  String search = '';
  final controller = TextEditingController();
  final Set<String> pending = {};
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  Future<void> checkIn(String guestId) async {
    setState(() => pending.add(guestId));
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('checkInGuestManually').call({
        'eventId': widget.eventId, 'guestId': guestId
      });
      if (!mounted) return;
      final status = result.data['status'];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        status == 'checked_in' ? 'Valid — checked in: ${result.data['guestName']}' : 'Already checked in'
      )));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check-in failed: $e')));
    } finally { if (mounted) setState(() => pending.remove(guestId)); }
  }
  @override
  Widget build(BuildContext context) {
    final guests = FirebaseFirestore.instance.collection('events').doc(widget.eventId).collection('guests').orderBy('name');
    return Scaffold(
      appBar: AppBar(title: const Text('Manual guest check-in')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          controller: controller,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search name or phone', border: OutlineInputBorder()),
          onChanged: (value) => setState(() => search = value.trim().toLowerCase()),
        )),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: guests.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Guest lookup unavailable: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs.where((d) {
              final data = d.data();
              return (data['name'] ?? '').toString().toLowerCase().contains(search) ||
                (data['phone'] ?? '').toString().toLowerCase().contains(search);
            }).toList();
            if (docs.isEmpty) return const Center(child: Text('No matching guests.'));
            return ListView.builder(itemCount: docs.length, itemBuilder: (context, i) {
              final doc = docs[i], data = doc.data();
              final checked = data['checkedIn'] == true;
              return ListTile(
                title: Text(data['name'] ?? 'Guest'),
                subtitle: Text(data['phone'] ?? data['email'] ?? ''),
                trailing: checked ? const Chip(label: Text('Checked in')) : FilledButton(
                  onPressed: pending.contains(doc.id) ? null : () => checkIn(doc.id),
                  child: pending.contains(doc.id) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator()) : const Text('Check in'),
                ),
              );
            });
          },
        )),
      ]),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.eventId, required this.eventTitle});
  final String eventId, eventTitle;
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}
class _ScannerPageState extends State<ScannerPage> {
  bool busy = false;
  String message = 'Scan a guest QR ticket';
  Color resultColor = Colors.black;
  Future<void> process(String raw) async {
    if (busy) return;
    setState(() { busy = true; message = 'Verifying ticket…'; resultColor = Colors.black; });
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map || parsed['v'] != 1 || parsed['e'] != widget.eventId || parsed['c'] is! String) throw const FormatException();
      final result = await FirebaseFunctions.instance.httpsCallable('checkInTicket').call({'eventId': widget.eventId, 'credential': parsed['c']});
      final status = result.data['status'];
      setState(() {
        if (status == 'checked_in') { message = 'Valid — checked in: ${result.data['guestName']}'; resultColor = Colors.green; }
        else if (status == 'already_checked_in') { message = 'Already checked in'; resultColor = Colors.orange; }
        else { message = 'Invalid ticket'; resultColor = Colors.red; }
      });
    } on FormatException { setState(() { message = 'Invalid ticket format or wrong event'; resultColor = Colors.red; }); }
    on FirebaseFunctionsException catch (e) { setState(() { message = e.message ?? 'Check-in failed. Check connection and access.'; resultColor = Colors.red; }); }
    catch (_) { setState(() { message = 'Could not verify. Check your internet connection.'; resultColor = Colors.red; }); }
    finally { await Future<void>.delayed(const Duration(seconds: 2)); if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Scan • ${widget.eventTitle}')), body: Column(children: [
    Expanded(child: MobileScanner(onDetect: (capture) { final value = capture.barcodes.firstOrNull?.rawValue; if (value != null) process(value); })),
    Container(width: double.infinity, padding: const EdgeInsets.all(20), color: Theme.of(context).colorScheme.surfaceContainer, child: Column(children: [
      Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: resultColor)),
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManualCheckInPage(eventId: widget.eventId))), icon: const Icon(Icons.search), label: const Text('Find guest manually')),
    ])),
  ]));
}

Future<void> _manualLookup(BuildContext context, String eventId, Future<void> Function(String) process) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Manual ticket check'), content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Paste ticket QR data')), actions: [
    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
    FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Verify')),
  ]));
  controller.dispose();
  if (value != null && value.trim().isNotEmpty) await process(value.trim());
}

String sha256Ticket(String credential) => sha256.convert(utf8.encode(credential)).toString();
