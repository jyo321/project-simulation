namespace Northbridge.Shared.Entities;

public class Applicant
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string FirstName { get; set; } = default!;
    public string LastName { get; set; } = default!;
    public string Email { get; set; } = default!;
    public string Phone { get; set; } = default!;
    public DateTimeOffset CreatedAt { get; set; }

    public List<LoanApplication> LoanApplications { get; set; } = new();
}
