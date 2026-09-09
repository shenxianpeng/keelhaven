import KeelhavenCore

/// A plan's at-a-glance health, distinct from `PlanRunState` because an idle
/// plan after a failed run and an idle plan that never ran both read as
/// "idle" there but need different colors/summaries here.
enum PlanHealth {
    case running
    case ok
    case neverBackedUp
    case needsAttention
}

extension BackupPlan {
    func health(runState: PlanRunState) -> PlanHealth {
        switch runState {
        case .running, .checking, .previewing, .pruning, .unlocking:
            return .running
        case .failed, .failedLocked:
            return .needsAttention
        case .succeeded:
            return .ok
        case .idle:
            // A failed integrity check outranks a good backup: the backups
            // exist but may not be restorable, which is the one thing this
            // dot must never show green for.
            if let lastCheck, !lastCheck.success { return .needsAttention }
            guard let lastRun else { return .neverBackedUp }
            return lastRun.success ? .ok : .needsAttention
        }
    }
}
