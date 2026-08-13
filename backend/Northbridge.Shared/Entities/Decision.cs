using Northbridge.Shared.Enums;

namespace Northbridge.Shared.Entities;

public class Decision
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LoanApplicationId { get; set; }
    public LoanApplication? LoanApplication { get; set; }

    public Guid ReviewerId { get; set; }
    public DecisionOutcome Outcome { get; set; }
    public string Reason { get; set; } = default!;

    /// <summary>Set when the ApprovalLetter has been generated into the generated-documents bucket.</summary>
    public string? ApprovalLetterObjectKey { get; set; }

    public DateTimeOffset DecidedAt { get; set; }
}
