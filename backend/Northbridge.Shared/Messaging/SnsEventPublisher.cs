using System.Text.Json;
using Amazon.SimpleNotificationService;
using Amazon.SimpleNotificationService.Model;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Northbridge.Shared.Messaging;

public class MessagingOptions
{
    public string ApplicationEventsTopicArn { get; set; } = default!;
    public string CreditScoringQueueUrl { get; set; } = default!;
    public string FraudAnalysisQueueUrl { get; set; } = default!;
    public string DocumentValidationQueueUrl { get; set; } = default!;
}

public class SnsEventPublisher : IEventPublisher
{
    private readonly IAmazonSimpleNotificationService _sns;
    private readonly MessagingOptions _options;
    private readonly ILogger<SnsEventPublisher> _logger;

    public SnsEventPublisher(IAmazonSimpleNotificationService sns, IOptions<MessagingOptions> options, ILogger<SnsEventPublisher> logger)
    {
        _sns = sns;
        _options = options.Value;
        _logger = logger;
    }

    public async Task PublishAsync<TEvent>(TEvent @event, CancellationToken ct = default) where TEvent : class
    {
        var eventType = typeof(TEvent).Name;
        var message = JsonSerializer.Serialize(@event);

        await _sns.PublishAsync(new PublishRequest
        {
            TopicArn = _options.ApplicationEventsTopicArn,
            Message = message,
            MessageAttributes = new Dictionary<string, MessageAttributeValue>
            {
                ["EventType"] = new MessageAttributeValue { DataType = "String", StringValue = eventType },
            },
        }, ct);

        _logger.LogInformation("Published {EventType} to application-events", eventType);
    }
}
