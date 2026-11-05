import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/features/remote/remote_home.dart';
import 'package:smriti_assist/services/api_client.dart';

http.Response _j(int s, Object b) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

Widget _app(ApiClient api, {VoidCallback? signedOut, String role = 'caretaker'}) => MaterialApp(
    home: RemoteHome(
        key: UniqueKey(),
        api: api,
        user: ServerUser('u', role, 'Ravi'),
        lang: 'en',
        onLogout: () {},
        onSignedOut: signedOut));

ApiClient _api(Future<http.Response> Function(http.Request) h) => ApiClient(
    baseUrl: 'https://api.example.com',
    tokens: MemoryTokenStore(),
    client: MockClient(h));

const _patientsJson = [
  {
    'patient_id': 'p1',
    'display_name': 'Asha',
    'link_role': 'caretaker',
    'alerts_needing_attention': 1,
    'last_played': '2020-01-01T10:00:00',
    'games_played_7d': 4,
    'streak': 0,
    'alerts': [
      {'kind': 'inactive', 'severity': 'attention', 'a': 5, 'b': 0}
    ],
  },
  {
    'patient_id': 'p2',
    'display_name': 'Babul',
    'link_role': 'caretaker',
    'alerts_needing_attention': 0,
    'last_played': null,
    'games_played_7d': 0,
    'streak': 0,
    'alerts': [],
  },
];

const _report = {
  'patient': {'id': 'p1', 'display_name': 'Asha', 'baseline_level': 2},
  'range_days': 7,
  'games_played': 4,
  'streak': 2,
  'last_played': '2026-03-10T10:00:00',
  'daily': [0, 1, 0, 2, 1, 0, 0],
  'per_game': [
    {'game': 'memory_match', 'sessions': 4, 'accuracy': 0.75}
  ],
  'adherence': {'expected': 6, 'done': 3},
  'alerts': [
    {'kind': 'inactive', 'severity': 'attention', 'a': 3, 'b': 0}
  ],
};

void main() {
  testWidgets('shows invitations and patients, and accepts an invite', (t) async {
    var accepted = false;
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites/i1/accept') {
        accepted = true;
        return _j(200, {'status': 'accepted'});
      }
      if (p == '/v1/invites') {
        return _j(200, accepted
            ? []
            : [
                {
                  'id': 'i1',
                  'patient_display_name': 'Meera',
                  'member_role': 'caretaker',
                  'created_at': '2026-03-01T00:00:00'
                }
              ]);
      }
      if (p == '/v1/my-patients') {
        return _j(200, [
          {
            'patient_id': 'p1',
            'display_name': 'Asha',
            'link_role': 'caretaker',
            'alerts_needing_attention': 1
          }
        ]);
      }
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    // The dashboard lists only people who already share; a request is not one.
    expect(find.text('Meera'), findsNothing);
    expect(find.text('Asha'), findsWidgets);
    // Requests have their own tab, with a badge and the person's Care ID.
    await t.tap(find.text('Requests'));
    await t.pumpAndSettle();
    expect(find.text('Meera'), findsOneWidget);
    expect(find.byKey(const ValueKey('careIdCard')), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(accepted, isTrue);
    expect(find.text('Meera'), findsNothing);
    expect(find.byKey(const ValueKey('noRequests')), findsOneWidget);
  });

  testWidgets('opening a patient shows the shared report and alerts', (t) async {
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') {
        return _j(200, [
          {
            'patient_id': 'p1',
            'display_name': 'Asha',
            'link_role': 'caretaker',
            'alerts_needing_attention': 0
          }
        ]);
      }
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha').first);
    await t.pumpAndSettle();
    expect(find.text('Has not played for 3 days.'), findsOneWidget);
    expect(find.text('Games played'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await t.tap(find.text('Games').last); // the Games pill on the patient screen
    await t.pumpAndSettle();
    expect(find.textContaining('75%'), findsOneWidget);
  });

  testWidgets('a revoked share is explained, an expired login signs out', (t) async {
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') {
        return _j(200, [
          {'patient_id': 'p1', 'display_name': 'Asha', 'alerts_needing_attention': 0}
        ]);
      }
      return _j(404, {'detail': 'not_found'});
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha').first);
    await t.pumpAndSettle();
    expect(find.text('This person is no longer sharing with you.'), findsOneWidget);

    var out = false;
    final expired = _api((r) async => _j(401, {'detail': 'invalid_token'}));
    await t.pumpWidget(_app(expired, signedOut: () => out = true));
    await t.pumpAndSettle();
    expect(out, isTrue);
  });

  testWidgets('dashboard, patients, alerts and settings tabs', (t) async {
    String? lang;
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') return _j(200, _patientsJson);
      if (p == '/v1/patients/p1/reminders') {
        return _j(200, [
          {'id': 'r1', 'kind': 'medicine', 'hour': 9, 'minute': 0, 'days_mask': 127, 'on_date': null, 'active': true, 'done_today': true},
          {'id': 'r2', 'kind': 'hydration', 'hour': 10, 'minute': 30, 'days_mask': 127, 'on_date': null, 'active': false, 'done_today': false},
        ]);
      }
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      if (p == '/v1/patients/p1/care-reminders') return _j(200, []);
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(MaterialApp(
        home: RemoteHome(
            api: api,
            user: const ServerUser('u', 'doctor', 'Dr Rao'),
            lang: 'en',
            onLangChanged: (l) => lang = l,
            onLogout: () {})));
    await t.pumpAndSettle();

    // dashboard: counts and recent activity, doctor wording
    expect(find.text('Your patients, at a glance'), findsOneWidget);
    expect(find.text('Asha'), findsWidgets);
    expect(find.textContaining('Played a game'), findsWidgets);
    expect(find.text('No games yet', skipOffstage: false), findsOneWidget);

    // patients tab: search and status chips
    await t.tap(find.text('Patients').last);
    await t.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Playing as usual'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'bab');
    await t.pumpAndSettle();
    expect(find.text('Asha'), findsNothing);
    expect(find.text('Babul'), findsOneWidget);

    // alerts page (a doctor reaches it from the bell on Home): the alert, named by patient
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.notifications_none_rounded).first);
    await t.pumpAndSettle();
    expect(find.text('Has not played for 5 days.'), findsOneWidget);

    // patient reminders tab shows times, done marks and switched-off ones
    await t.tap(find.text('Has not played for 5 days.'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reminders').last);
    await t.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('Done today'), findsOneWidget);
    expect(find.textContaining('10:30'), findsOneWidget);
    expect(find.textContaining('Off'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    // settings: language change is reported, about opens
    await t.tap(find.text('Profile').last);
    await t.pumpAndSettle();
    for (final k in ['rowHelp', 'rowAbout', 'rowSos']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
    await t.tap(find.byKey(const ValueKey('rowProfile')));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView).last, const Offset(0, -400));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('languageRow')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('lang_hi')));
    await t.pumpAndSettle();
    expect(lang, 'hi');
    expect(find.text('Dr Rao'), findsWidgets);
  });

  testWidgets('a caregiver adds a routine for the patient, sees who added what, deletes their own', (t) async {
    final care = <Map<String, dynamic>>[
      {'id': 'x1', 'kind': 'hydration', 'label': 'Drink water', 'hour': 10, 'minute': 0,
       'days_mask': 127, 'on_date': null, 'created_by_name': 'Dr Rao', 'created_by_role': 'doctor', 'mine': false},
    ];
    Map<String, dynamic>? posted;
    Map<String, dynamic>? edited;
    final deleted = <String>[];
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') return _j(200, _patientsJson);
      if (p == '/v1/patients/p1/reminders') return _j(200, []);
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      if (p == '/v1/patients/p1/care-reminders' && r.method == 'POST') {
        posted = jsonDecode(r.body) as Map<String, dynamic>;
        care.add({'id': 'x2', ...posted!, 'days_mask': 127, 'created_by_name': 'Ravi',
                  'created_by_role': 'caretaker', 'mine': true});
        return _j(201, care.last);
      }
      if (p.startsWith('/v1/patients/p1/care-reminders/') && r.method == 'PATCH') {
        edited = jsonDecode(r.body) as Map<String, dynamic>;
        final i = care.indexWhere((x) => x['id'] == p.split('/').last);
        care[i] = {...care[i], ...edited!};
        return _j(200, care[i]);
      }
      if (p.startsWith('/v1/patients/p1/care-reminders/') && r.method == 'DELETE') {
        deleted.add(p.split('/').last);
        care.removeWhere((x) => x['id'] == p.split('/').last);
        return http.Response('', 204);
      }
      if (p == '/v1/patients/p1/care-reminders') return _j(200, care);
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Reminders').last);
    await t.pumpAndSettle();
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Added by Dr Rao'), findsOneWidget);
    expect(find.byKey(const ValueKey('deleteCare_x1')), findsNothing); // not theirs
    await t.tap(find.byKey(const ValueKey('addCareReminder')));
    await t.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(find.textContaining('Your name'), findsNothing);
    await t.tap(find.byType(DropdownButtonFormField<ReminderKind>));
    await t.pumpAndSettle();
    expect(find.text('Medicine'), findsNothing);
    expect(find.text('Appointment'), findsWidgets);
    await t.tap(find.text('Water').last);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Morning tablet');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(posted!['label'], 'Morning tablet');
    expect(posted!['kind'], 'hydration'); // a caregiver cannot prescribe medicines
    expect([posted!['hour'], posted!['minute']], [9, 0]);
    expect(find.text('Added by Ravi'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('editCare_x2')));
    await t.pumpAndSettle();
    expect(find.text('Morning tablet'), findsWidgets); // the dialog is filled in
    await t.enterText(find.byType(TextField).last, 'Morning walk');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(edited!['label'], 'Morning walk');
    expect(edited!['kind'], 'hydration');
    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.byKey(const ValueKey('editCare_x1')), findsNothing); // not theirs
    await t.tap(find.byKey(const ValueKey('deleteCare_x2')));
    await t.pumpAndSettle();
    expect(deleted, ['x2']);
    expect(find.text('Morning walk'), findsNothing);
  });

  testWidgets('a doctor prescribes a medicine and schedules an appointment', (t) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final posts = <Map<String, dynamic>>[];
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') return _j(200, _patientsJson);
      if (p == '/v1/patients/p1/reminders') return _j(200, []);
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      if (p == '/v1/patients/p1/care-reminders' && r.method == 'POST') {
        posts.add(jsonDecode(r.body) as Map<String, dynamic>);
        return _j(201, {'id': 'd${posts.length}', ...posts.last, 'days_mask': 127,
                        'created_by_name': 'Ravi', 'created_by_role': 'doctor', 'mine': true});
      }
      if (p == '/v1/patients/p1/care-reminders') return _j(200, []);
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api, role: 'doctor'));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Reminders').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('addCareReminder')));
    await t.pumpAndSettle();
    // A prescription: name, dose, when to take it, and how many times a day.
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull,
        reason: 'no medicine name yet');
    await t.enterText(find.byKey(const ValueKey('rxName')), 'Metformin');
    await t.enterText(find.byKey(const ValueKey('rxDose')), '500 mg');
    await t.tap(find.byKey(const ValueKey('food_after')));
    await t.tap(find.byKey(const ValueKey('rxPreset2'))); // twice a day: 8:00 and 20:00
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(posts.length, 2); // one reminder for each time
    expect(posts.map((x) => x['kind']), ['medicine', 'medicine']); // a doctor's first choice
    expect(posts.map((x) => x['label']).toSet(), {'Metformin · 500 mg · After food'});
    expect(posts.map((x) => x['hour']), [8, 20]);
    await t.tap(find.byKey(const ValueKey('addCareReminder')));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<ReminderKind>));
    await t.pumpAndSettle();
    await t.tap(find.text('Appointment').last);
    await t.pumpAndSettle();
    expect(find.text('Medicine'), findsNothing);
  });

  testWidgets('the patient screen opens with a header: name, status and quick actions', (t) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') return _j(200, _patientsJson);
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      if (p == '/v1/patients/p1/reminders') return _j(200, []);
      if (p == '/v1/patients/p1/care-reminders') return _j(200, []);
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(MaterialApp(
        home: RemotePatientScreen(
            api: api, patientId: 'p1', name: 'Asha Devi', lang: 'en',
            canPrescribe: true, accent: Colors.blue, onMessage: () {})));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('patientHero')), findsOneWidget);
    expect(find.text('Asha Devi'), findsOneWidget);
    expect(find.text('Needs attention'), findsWidgets); // the report has an attention alert
    expect(find.byKey(const ValueKey('heroMessage')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('heroRoutine')));
    await t.pumpAndSettle();
    expect(find.text('Add reminder'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('heroReport')));
    await t.pumpAndSettle();
    expect(find.byType(RemoteReportScreen), findsOneWidget);
  });

  testWidgets('the dashboard lists patients needing attention before recent activity', (t) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final api = _api((r) async {
      if (r.url.path == '/v1/invites') return _j(200, []);
      if (r.url.path == '/v1/my-patients') return _j(200, _patientsJson);
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api, role: 'doctor'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('roleHero')), findsOneWidget);
    final attention = t.getTopLeft(find.text('Needs attention').first).dy;
    final recent = t.getTopLeft(find.text('Recent activity')).dy;
    expect(attention, lessThan(recent));
    // Babul has no alert: only Asha is in the attention list, so Asha shows twice.
    expect(find.text('Asha'), findsNWidgets(2));
    expect(find.text('Babul'), findsOneWidget);
  });

  testWidgets('a doctor has a Consult tab: own patients and other patients\' questions, and caregivers of own patients', (t) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') return _j(200, _patientsJson);
      if (p == '/v1/chat/threads') {
        return _j(200, [
          {'link_id': 'L1', 'kind': 'care', 'patient_id': 'p1', 'patient_name': 'Asha', 'peer_name': 'Asha',
           'member_role': 'doctor', 'unread': 1, 'last_at': '2026-05-01T10:00:00', 'last_kind': 'text'},
          {'link_id': 'C7', 'kind': 'opinion', 'patient_id': null, 'patient_name': 'Stranger Sen', 'peer_name': 'Stranger Sen',
           'member_role': 'patient', 'unread': 2, 'last_at': '2026-05-02T10:00:00', 'last_kind': 'text'},
          {'link_id': 'P1', 'kind': 'pro', 'patient_id': null, 'patient_name': 'Asha', 'peer_name': 'Cara Caregiver',
           'member_role': 'caretaker', 'unread': 0, 'last_at': null, 'last_kind': null},
        ]);
      }
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api, role: 'doctor'));
    await t.pumpAndSettle();
    // the doctor's bar: Home, Patients, Consult, Requests, Profile (alerts is the bell)
    final nav = find.byType(NavigationBar);
    for (final l in ['Home', 'Patients', 'Consult', 'Requests', 'Profile']) {
      expect(find.descendant(of: nav, matching: find.text(l)), findsOneWidget, reason: l);
    }
    expect(find.descendant(of: nav, matching: find.text('Alerts')), findsNothing);
    await t.tap(find.descendant(of: nav, matching: find.text('Consult')));
    await t.pumpAndSettle();
    expect(find.text('Your patients'), findsOneWidget);
    expect(find.text('Questions from other patients'), findsOneWidget);
    expect(find.text('Stranger Sen'), findsOneWidget);
    expect(find.text('Opinion request'), findsOneWidget);
    expect(find.text('Cara Caregiver'), findsNothing); // caregivers are in their own section
    await t.tap(find.byKey(const ValueKey('consultSegCaregivers')));
    await t.pumpAndSettle();
    expect(find.text('Cara Caregiver'), findsOneWidget);
    expect(find.textContaining('Care team chat'), findsOneWidget);
    expect(find.text('Stranger Sen'), findsNothing);
    // the bell still reaches the alerts page
    await t.tap(find.descendant(of: nav, matching: find.text('Home')));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.notifications_none_rounded).first);
    await t.pumpAndSettle();
    expect(find.text('Alerts'), findsWidgets);
  });

  testWidgets('a caregiver has no Consult tab', (t) async {
    final api = _api((r) async {
      if (r.url.path == '/v1/invites') return _j(200, []);
      if (r.url.path == '/v1/my-patients') return _j(200, _patientsJson);
      return _j(200, <Object>[]);
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Consult')), findsNothing);
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Alerts')), findsOneWidget);
  });

  testWidgets('editing a prescription shows its name, dose and food timing; only one time', (t) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    Map<String, dynamic>? edited;
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') return _j(200, _patientsJson);
      if (p == '/v1/patients/p1/reminders') return _j(200, []);
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      if (p.startsWith('/v1/patients/p1/care-reminders/') && r.method == 'PATCH') {
        edited = jsonDecode(r.body) as Map<String, dynamic>;
        return _j(200, {'id': 'm1', 'kind': 'medicine', 'label': edited!['label'], 'hour': 21, 'minute': 0,
                        'days_mask': 127, 'created_by_name': 'Ravi', 'created_by_role': 'doctor', 'mine': true});
      }
      if (p == '/v1/patients/p1/care-reminders') {
        return _j(200, [
          {'id': 'm1', 'kind': 'medicine', 'label': 'Metformin · 500 mg · After food', 'hour': 20,
           'minute': 0, 'days_mask': 127, 'on_date': null, 'created_by_name': 'Ravi',
           'created_by_role': 'doctor', 'mine': true}
        ]);
      }
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api, role: 'doctor'));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Reminders').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('editCare_m1')));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const ValueKey('rxName'))).controller!.text, 'Metformin');
    expect(t.widget<TextField>(find.byKey(const ValueKey('rxDose'))).controller!.text, '500 mg');
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('food_after'))).selected, isTrue);
    expect(find.byKey(const ValueKey('rxAddTime')), findsNothing);
    expect(find.byKey(const ValueKey('rxPreset2')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('rxDose')), '1000 mg');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(edited!['label'], 'Metformin · 1000 mg · After food');
  });

  testWidgets('requests: invitations show who and how long ago; the how-it-works guide is there', (t) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    var invites = [
      {'id': 'i1', 'patient_display_name': 'Meera Sen', 'member_role': 'doctor',
       'created_at': DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String()}
    ];
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, invites);
      if (p == '/v1/my-patients') return _j(200, <Object>[]);
      if (p == '/v1/invites/i1/accept') {
        invites = [];
        return _j(200, {});
      }
      return _j(200, <Object>[]);
    });
    await t.pumpWidget(_app(api, role: 'doctor'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Requests')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('invite_i1')), findsOneWidget);
    expect(find.textContaining('Invited you as Doctor'), findsOneWidget);
    expect(find.textContaining('3 hours ago'), findsOneWidget);
    expect(find.byKey(const ValueKey('howLinking')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('accept_i1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('invite_i1')), findsNothing);
    expect(find.byKey(const ValueKey('noRequests')), findsOneWidget);
  });

  testWidgets('alerts: urgent first, a back arrow for a doctor, and it leads to the patient', (t) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') {
        return _j(200, [
          {..._patientsJson[0], 'alerts_needing_attention': 1, 'alerts': [
            {'kind': 'tip_low_accuracy', 'severity': 'info', 'a': 50, 'b': 0},
            {'kind': 'inactive', 'severity': 'attention', 'a': 5, 'b': 0},
          ]},
        ]);
      }
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      return _j(200, <Object>[]);
    });
    await t.pumpWidget(_app(api, role: 'doctor'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.notifications_none_rounded).first);
    await t.pumpAndSettle();
    expect(find.text('Good to know'), findsOneWidget);
    final urgent = t.getTopLeft(find.text('Has not played for 5 days.')).dy;
    final gentle = t.getTopLeft(find.text('Good to know')).dy;
    expect(urgent, lessThan(gentle));
    await t.tap(find.text('Has not played for 5 days.'));
    await t.pumpAndSettle();
    expect(find.byType(RemotePatientScreen), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('alertsBack')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('roleHero')), findsOneWidget);
  });
}
