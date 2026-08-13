using Northbridge.Shared.Enums;

namespace Northbridge.Shared.Entities;

public class LoanApplication
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ApplicantId { get; set; }
    public Applicant? Applicant { get; set; }

    public decimal RequestedAmount { get; set; }
    public string Purpose { get; set; } = default!;
    public LoanApplicationStatus Status { get; set; } = LoanApplicationStatus.Draft;

    /// <summary>Populated asynchronously by the CreditScoringJob fire-and-forget worker.</summary>
    public int? RiskScore { get; set; }

    /// <summary>Populated asynchronously by the FraudForensicsJob fire-and-forget worker.</summary>
    public bool FraudFlagged { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? SubmittedAt { get; set; }
    public DateTimeOffset? DecidedAt { get; set; }

    public List<Document> Documents { get; set; } = new();
    public Decision? Decision { get; set; }
    public CreditReport? CreditReport { get; set; }
}
