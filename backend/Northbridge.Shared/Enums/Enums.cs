namespace Northbridge.Shared.Enums;

public enum LoanApplicationStatus
{
    Draft,
    Submitted,
    DocumentsPending,
    UnderReview,
    Approved,
    Rejected,
}

public enum DocumentType
{
    IdentityProof,
    IncomeProof,
    BankStatement,
    Other,
}

public enum DocumentStatus
{
    Uploaded,
    Validating,
    Validated,
    Rejected,
}

public enum DecisionOutcome
{
    Approved,
    Rejected,
}

/// <summary>Distinguishes the two fire-and-forget (&gt;20 min) job types from the brief.</summary>
public enum JobType
{
    CreditScoring,
    FraudForensics,
}

public enum JobStatus
{
    Queued,
    Running,
    Succeeded,
    Failed,
}

public enum NotificationChannel
{
    Email,
    Sms,
}

public enum NotificationStatus
{
    Pending,
    Sent,
    Failed,
    DeadLettered,
}
