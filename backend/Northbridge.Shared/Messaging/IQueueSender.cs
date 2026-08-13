namespace Northbridge.Shared.Messaging;

/// <summary>
/// Enqueues work onto a specific SQS queue. Used by the API layer to kick off fire-and-forget
/// (&gt;20 min) jobs and service-triggered workers without blocking the HTTP request thread.
/// </summary>
public interface IQueueSender
{
    Task SendAsync(string queueUrl, object payload, CancellationToken ct = default);
}
