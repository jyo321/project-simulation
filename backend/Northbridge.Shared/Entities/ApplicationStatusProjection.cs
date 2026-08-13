namespace Northbridge.Shared.Entities;

/// <summary>
/// Denormalized read model maintained by the Application Status Projector worker. Decouples
/// the Reviewer Console's read path from the Applications API's transactional write path —
/// the projector is the only writer, keyed by LoanApplicationId.
/// </summary>
public class ApplicationStatusProjection
{
    public Guid LoanApplicationId { get; set; }
    public string Status { get; set; } = default!;
    public DateTimeOffset UpdatedAt { get; set; }
}
