class SnapshotBase { long value; };
class SnapshotParticipant { long value; };
typedef struct SnapshotDelegate { delegate SnapshotBase base; } SnapshotDelegate;

protocol SnapshotBase(T) { long T.measure(T); }
long SnapshotBase.measure(SnapshotBase value) => value.value;
long SnapshotParticipant.measure(SnapshotParticipant value) => value.value;
protocol SnapshotBase(SnapshotParticipant);

long snapshot_protocol(SnapshotParticipant value) => value.measure();
