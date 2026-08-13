namespace Applications.Api.Dtos;

public record CreateLoanApplicationRequest(Guid ApplicantId, decimal RequestedAmount, string Purpose);

public record LoanApplicationResponse(
    Guid Id,
    Guid ApplicantId,
    decimal RequestedAmount,
    string Purpose,
    string Status,
    int? RiskScore,
    DateTimeOffset CreatedAt,
    DateTimeOffset? SubmittedAt,
    DateTimeOffset? DecidedAt);
