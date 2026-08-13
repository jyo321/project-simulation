using Northbridge.Shared.Enums;

namespace Northbridge.Shared.Entities;

/// <summary>Audit trail for the Notification Worker — one row per attempted send, for support/debugging.</summary>
public class NotificationLogEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ApplicantId { get; set; }
    public NotificationChannel Channel { get; set; }
    public string TemplateKey { get; set; } = default!;
    public string Payload { get; set; } = default!;
    public NotificationStatus Status { get; set; } = NotificationStatus.Pending;
    public int Attempts { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? SentAt { get; set; }
}
