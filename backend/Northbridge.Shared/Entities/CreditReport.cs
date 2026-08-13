namespace Northbridge.Shared.Entities;

/// <summary>Written by the CreditScoringJob fire-and-forget worker once the mock bureau call completes.</summary>
public class CreditReport
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LoanApplicationId { get; set; }
    public LoanApplication? LoanApplication { get; set; }

    public int Score { get; set; }
    public string BureauReference { get; set; } = default!;
    public string RawResponseBucket { get; set; } = default!;
    public string RawResponseObjectKey { get; set; } = default!;

    public DateTimeOffset PulledAt { get; set; }
}
