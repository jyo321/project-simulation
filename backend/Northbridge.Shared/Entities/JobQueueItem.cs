using Northbridge.Shared.Enums;

namespace Northbridge.Shared.Entities;

/// <summary>
/// Tracks a fire-and-forget (&gt;20 min) job from the moment an API enqueues it until the
/// ECS RunTask worker reports completion. Written in the same transaction as the SQS enqueue
/// so the API never depends on the queue send succeeding to know a job was requested.
/// </summary>
public class JobQueueItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public JobType JobType { get; set; }
    public Guid LoanApplicationId { get; set; }
    public JobStatus Status { get; set; } = JobStatus.Queued;

    public string? ErrorMessage { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
}
