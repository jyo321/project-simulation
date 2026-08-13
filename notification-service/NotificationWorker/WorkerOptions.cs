namespace NotificationWorker;

public class WorkerOptions
{
    public string NotificationsQueueUrl { get; set; } = default!;
    public string SenderEmail { get; set; } = default!;
    public int MaxInProcessAttempts { get; set; } = 5;
}
