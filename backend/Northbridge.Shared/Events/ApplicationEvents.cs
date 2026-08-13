namespace Northbridge.Shared.Events;

/// <summary>
/// Contracts published to the "application-events" SNS topic. The Status Projector Worker and
/// the Notification Worker each subscribe an SQS queue to this topic and react independently.
/// </summary>
public abstract record ApplicationEvent
{
    public Guid LoanApplicationId { get; init; }
    public DateTimeOffset OccurredAt { get; init; }
}

public sealed record ApplicationStatusChangedEvent : ApplicationEvent
{
    public string PreviousStatus { get; init; } = default!;
    public string NewStatus { get; init; } = default!;
}

public sealed record DecisionMadeEvent : ApplicationEvent
{
    public Guid ApplicantId { get; init; }
    public string Outcome { get; init; } = default!;
    public string Reason { get; init; } = default!;
}

public sealed record CreditScoringCompletedEvent : ApplicationEvent
{
    public int RiskScore { get; init; }
}

public sealed record FraudForensicsCompletedEvent : ApplicationEvent
{
    public bool FlaggedForFraud { get; init; }
}
