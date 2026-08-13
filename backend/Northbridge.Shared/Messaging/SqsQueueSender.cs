using System.Text.Json;
using Amazon.SQS;
using Amazon.SQS.Model;
using Microsoft.Extensions.Logging;

namespace Northbridge.Shared.Messaging;

public class SqsQueueSender : IQueueSender
{
    private readonly IAmazonSQS _sqs;
    private readonly ILogger<SqsQueueSender> _logger;

    public SqsQueueSender(IAmazonSQS sqs, ILogger<SqsQueueSender> logger)
    {
        _sqs = sqs;
        _logger = logger;
    }

    public async Task SendAsync(string queueUrl, object payload, CancellationToken ct = default)
    {
        var body = JsonSerializer.Serialize(payload);
        await _sqs.SendMessageAsync(new SendMessageRequest
        {
            QueueUrl = queueUrl,
            MessageBody = body,
        }, ct);

        _logger.LogInformation("Enqueued message to {QueueUrl}", queueUrl);
    }
}
