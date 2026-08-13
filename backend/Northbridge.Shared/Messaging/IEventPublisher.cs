namespace Northbridge.Shared.Messaging;

/// <summary>Publishes domain events to the SNS "application-events" topic (fan-out backbone).</summary>
public interface IEventPublisher
{
    Task PublishAsync<TEvent>(TEvent @event, CancellationToken ct = default) where TEvent : class;
}
