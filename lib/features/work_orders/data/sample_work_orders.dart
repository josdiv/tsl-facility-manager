import '../domain/work_order.dart';

const sampleClient = 'Daniel Clarke';
const sampleStaff = 'Emeka Okafor';
const sampleSupervisor = 'Sarah James';
const _marina = 'Marina Towers, Lagos';

/// Sample orders from the prototype. Due times are relative to [now] so the
/// overdue flag behaves the same whenever the app is opened.
List<WorkOrder> sampleWorkOrders(DateTime now) {
  DateTime hours(int value) => now.add(Duration(hours: value));

  return [
    WorkOrder(
      id: 'WO-1048',
      title: 'AHU-02 cooling fault',
      description:
          'No cold air reaching the east office wing. Check condenser, filter '
          'and refrigerant pressure.',
      type: WorkOrderType.client,
      status: WorkOrderStatus.inProgress,
      location: _marina,
      zone: 'Tower A · Floor 3',
      due: hours(3),
      submittedBy: sampleClient,
      assignee: sampleStaff,
      isHighPriority: true,
      reportMedia: const ['Client-evidence.jpg', 'Unit-close-up.jpg'],
      history: [
        WorkOrderEvent('Issue reported', hours(-4)),
        WorkOrderEvent('Assigned to $sampleStaff', hours(-4)),
        WorkOrderEvent(
          'Technician working on it',
          hours(-3),
          note: 'Checking refrigerant pressure',
        ),
      ],
    ),
    WorkOrder(
      id: 'WO-1047',
      title: 'Monthly generator service',
      description: 'Scheduled monthly service for the plant room generator.',
      type: WorkOrderType.sla,
      status: WorkOrderStatus.open,
      location: _marina,
      zone: 'Plant room',
      due: hours(5),
      submittedBy: 'SLA schedule',
      assignee: sampleStaff,
      history: [WorkOrderEvent('Scheduled by SLA plan', hours(-24))],
    ),
    WorkOrder(
      id: 'WO-1045',
      title: 'Fire extinguisher inspection',
      description: 'Inspect and tag all fire extinguishers on every floor.',
      type: WorkOrderType.sla,
      status: WorkOrderStatus.open,
      location: _marina,
      zone: 'All floors',
      due: hours(-2),
      submittedBy: 'SLA schedule',
      assignee: sampleStaff,
      history: [WorkOrderEvent('Scheduled by SLA plan', hours(-48))],
    ),
    WorkOrder(
      id: 'WO-1043',
      title: 'Pump room leak check',
      description: 'Check the pump room seals for any sign of leakage.',
      type: WorkOrderType.sla,
      status: WorkOrderStatus.pendingReview,
      location: _marina,
      zone: 'Pump room',
      due: hours(2),
      submittedBy: 'SLA schedule',
      assignee: sampleStaff,
      workNote:
          'Replaced one worn seal. No further leakage after a 20 minute run.',
      workMedia: const ['Pump-seal.jpg'],
      submittedAt: hours(-1),
      history: [
        WorkOrderEvent('Scheduled by SLA plan', hours(-30)),
        WorkOrderEvent('Work submitted for review', hours(-1)),
      ],
    ),
    WorkOrder(
      id: 'WO-1041',
      title: 'Car park lighting repair',
      description: 'Two light fittings are out on car park level 1.',
      type: WorkOrderType.client,
      status: WorkOrderStatus.completed,
      location: _marina,
      zone: 'Car park',
      due: hours(-24),
      submittedBy: 'Reception desk',
      assignee: sampleStaff,
      workNote: 'Replaced both fittings and tested them.',
      workMedia: const ['Car-park.jpg'],
      submittedAt: hours(-26),
      history: [
        WorkOrderEvent('Issue reported', hours(-50)),
        WorkOrderEvent('Supervisor confirmed the work', hours(-25)),
      ],
    ),
    WorkOrder(
      id: 'WO-1040',
      title: 'Office door lock repair',
      description: 'The lock on the east office door is sticking.',
      type: WorkOrderType.client,
      status: WorkOrderStatus.completed,
      location: _marina,
      zone: 'Tower A · Floor 2',
      due: hours(-72),
      submittedBy: sampleClient,
      assignee: 'David Adeyemi',
      workNote: 'Replaced the lock cylinder.',
      workMedia: const ['Door-lock.jpg'],
      submittedAt: hours(-74),
      history: [
        WorkOrderEvent('Issue reported', hours(-96)),
        WorkOrderEvent('Assigned to David Adeyemi', hours(-95)),
        WorkOrderEvent('Supervisor confirmed the work', hours(-73)),
      ],
    ),
    WorkOrder(
      id: 'WO-1039',
      title: 'Washroom tap leakage',
      description: 'The tap in the Floor 3 washroom keeps dripping.',
      type: WorkOrderType.client,
      status: WorkOrderStatus.open,
      location: _marina,
      zone: 'Tower A · Floor 3',
      due: hours(24),
      submittedBy: sampleClient,
      assignee: 'Tunde Bakare',
      history: [
        WorkOrderEvent('Issue reported', hours(-2)),
        WorkOrderEvent('Assigned to Tunde Bakare', hours(-1)),
      ],
    ),
    WorkOrder(
      id: 'WO-1037',
      title: 'Corridor lighting',
      description: 'Lights are flickering along the Floor 4 corridor.',
      type: WorkOrderType.client,
      status: WorkOrderStatus.pendingReview,
      location: _marina,
      zone: 'Tower A · Floor 4',
      due: hours(4),
      submittedBy: sampleClient,
      assignee: 'Tunde Bakare',
      workNote: 'Replaced the faulty driver on the corridor circuit.',
      workMedia: const ['Corridor.jpg', 'Lights-on.jpg'],
      submittedAt: hours(-1),
      history: [
        WorkOrderEvent('Issue reported', hours(-20)),
        WorkOrderEvent('Assigned to Tunde Bakare', hours(-19)),
        WorkOrderEvent('Work submitted for review', hours(-1)),
      ],
    ),
  ];
}
