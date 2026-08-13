using System.Text.Json;
using Amazon.SimpleEmail;
using Amazon.SimpleEmail.Model;
using Amazon.SQS;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Data;
using Northbridge.Shared.Entities;
using Northbridge.Shared.Enums;
using Northbridge.Shared.Events;
using SqsMessage = Amazon.SQS.Model.Message;

namespace NotificationWorker;

/// <summary>
/// The Notification Service from the brief (§2.6): consumes the "notifications" SQS queue,
/// which is subscribed to the "application-events" SNS topic. Implements the two-layer retry
/// the brief calls for:
///   1. In-process exponential backoff + jitter across <see cref="WorkerOptions.MaxInProcessAttempts"/>
///      attempts within a single message receive.
///   2. SQS-level redelivery: if all in-process attempts fail, the message is left on the queue
///      (not deleted) so it becomes visible again and is retried on a future receive, up to the
///      queue's own maxReceiveCount redrive policy (infra/terraform/messaging.tf) — after which
///      SQS automatically moves it to "notifications-dlq" and a CloudWatch alarm fires.
/// </summary>
public class Worker : BackgroundService
{
    private readonly IAmazonSQS _sqs;
    private readonly IAmazonSimpleEmailService _ses;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly WorkerOptions _options;
    private readonly ILogger<Worker> _logger;

    public Worker(
        IAmazonSQS sqs,
        IAmazonSimpleEmailService ses,
        IServiceScopeFactory scopeFactory,
        IOptions<WorkerOptions> options,
        ILogger<Worker> logger)
    {
        _sqs = sqs;
        _ses = ses;
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var response = await _sqs.ReceiveMessageAsync(new Amazon.SQS.Model.ReceiveMessageRequest
            {
                QueueUrl = _options.NotificationsQueueUrl,
                MaxNumberOfMessages = 10,
                WaitTimeSeconds = 20,
                VisibilityTimeout = 60,
                MessageAttributeNames = new List<string> { "EventType" },
            }, stoppingToken);

            foreach (var message in response.Messages)
            {
                var handled = await TryProcessWithInProcessRetryAsync(message, stoppingToken);
                if (handled)
                {
                    await _sqs.DeleteMessageAsync(_options.NotificationsQueueUrl, message.ReceiptHandle, stoppingToken);
                }
                // else: leave the message on the queue for SQS-level redelivery / eventual DLQ.
            }
        }
    }

    private async Task<bool> TryProcessWithInProcessRetryAsync(SqsMessage message, CancellationToken ct)
    {
        var eventType = message.MessageAttributes.TryGetValue("EventType", out var attr) ? attr.StringValue : null;
        if (eventType != nameof(DecisionMadeEvent))
        {
            // Other event types on this topic are consumed by other workers; not our concern.
            return true;
        }

        var evt = JsonSerializer.Deserialize<DecisionMadeEvent>(message.Body);
        if (evt is null) return true;

        for (var attempt = 1; attempt <= _options.MaxInProcessAttempts; attempt++)
        {
            try
            {
                await SendDecisionNotificationAsync(evt, ct);
                return true;
            }
            catch (Exception ex) when (attempt < _options.MaxInProcessAttempts)
            {
                var delay = TimeSpan.FromMilliseconds(200 * Math.Pow(2, attempt - 1)) + TimeSpan.FromMilliseconds(Random.Shared.Next(0, 100));
                _logger.LogWarning(ex, "Notification attempt {Attempt}/{Max} failed for application {LoanApplicationId}; retrying in {Delay}ms",
                    attempt, _options.MaxInProcessAttempts, evt.LoanApplicationId, delay.TotalMilliseconds);
                await Task.Delay(delay, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Notification exhausted {Max} in-process attempts for application {LoanApplicationId}; leaving message for SQS redelivery",
                    _options.MaxInProcessAttempts, evt.LoanApplicationId);
                await LogFailureAsync(evt, ct);
                return false;
            }
        }

        return false;
    }

    private async Task SendDecisionNotificationAsync(DecisionMadeEvent evt, CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();

        var applicant = await db.Applicants.FindAsync([evt.ApplicantId], ct);
        if (applicant is null)
        {
            _logger.LogWarning("Applicant {ApplicantId} not found; dropping notification", evt.ApplicantId);
            return;
        }

        var subject = evt.Outcome == "Approved" ? "Your Northbridge loan application was approved" : "Update on your Northbridge loan application";
        var body = evt.Outcome == "Approved"
            ? $"Good news, {applicant.FirstName}! Your loan application has been approved."
            : $"Hi {applicant.FirstName}, unfortunately your loan application was not approved. Reason: {evt.Reason}";

        await _ses.SendEmailAsync(new SendEmailRequest
        {
            Source = "notifications@northbridgelending.com",
            Destination = new Destination { ToAddresses = new List<string> { applicant.Email } },
            Message = new Amazon.SimpleEmail.Model.Message
            {
                Subject = new Content(subject),
                Body = new Body { Text = new Content(body) },
            },
        }, ct);

        db.NotificationLogEntries.Add(new NotificationLogEntry
        {
            ApplicantId = applicant.Id,
            Channel = NotificationChannel.Email,
            TemplateKey = "decision-made",
            Payload = JsonSerializer.Serialize(evt),
            Status = NotificationStatus.Sent,
            Attempts = 1,
            CreatedAt = DateTimeOffset.UtcNow,
            SentAt = DateTimeOffset.UtcNow,
        });
        await db.SaveChangesAsync(ct);
    }

    private async Task LogFailureAsync(DecisionMadeEvent evt, CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();

        db.NotificationLogEntries.Add(new NotificationLogEntry
        {
            ApplicantId = evt.ApplicantId,
            Channel = NotificationChannel.Email,
            TemplateKey = "decision-made",
            Payload = JsonSerializer.Serialize(evt),
            Status = NotificationStatus.Failed,
            Attempts = _options.MaxInProcessAttempts,
            CreatedAt = DateTimeOffset.UtcNow,
        });
        await db.SaveChangesAsync(ct);
    }
}
