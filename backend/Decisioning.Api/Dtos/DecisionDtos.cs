namespace Decisioning.Api.Dtos;

public record ReviewerQueueItem(
    Guid LoanApplicationId,
    Guid ApplicantId,
    string ApplicantName,
    decimal RequestedAmount,
    string Purpose,
    string Status,
    int? RiskScore,
    bool FraudFlagged,
    DateTimeOffset? SubmittedAt);

public record MakeDecisionRequest(Guid ReviewerId, string Outcome, string Reason);

public record DecisionResponse(Guid LoanApplicationId, string Outcome, string Reason, DateTimeOffset DecidedAt);
