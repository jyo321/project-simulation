using Amazon.SimpleNotificationService;
using Amazon.SQS;
using Microsoft.EntityFrameworkCore;
using Northbridge.Shared.Aws;
using Northbridge.Shared.Data;
using Northbridge.Shared.Messaging;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddDbContext<NorthbridgeDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Northbridge")));

builder.Services.Configure<MessagingOptions>(builder.Configuration.GetSection("Messaging"));

builder.Services.AddDefaultAWSOptions(NorthbridgeAwsOptions.Build(builder.Configuration));
builder.Services.AddAWSService<IAmazonSimpleNotificationService>();
builder.Services.AddAWSService<IAmazonSQS>();

builder.Services.AddScoped<IEventPublisher, SnsEventPublisher>();
builder.Services.AddScoped<IQueueSender, SqsQueueSender>();

// Cognito issues the JWT the Applicant Portal attaches as a Bearer token. The ALB also
// validates the token at the edge (see infra/terraform/ecs.tf); this is defense in depth
// for any client that calls the API directly.
builder.Services.AddAuthentication().AddJwtBearer(options =>
{
    options.Authority = builder.Configuration["Cognito:Authority"];
    options.Audience = builder.Configuration["Cognito:AppClientId"];
});
builder.Services.AddAuthorization();

builder.Services.AddCors(options =>
{
    options.AddPolicy("SpaOrigins", policy =>
        policy.WithOrigins(builder.Configuration.GetSection("AllowedOrigins").Get<string[]>() ?? Array.Empty<string>())
            .AllowAnyHeader()
            .AllowAnyMethod());
});

builder.Services.AddHealthChecks();

var app = builder.Build();

// Applications.Api is the single migration-applying entry point — in a multi-service
// system, every instance racing to migrate on startup is a recipe for lock contention.
// A real release pipeline would instead run `dotnet ef database update` as its own
// pipeline step before any service starts; doing it here keeps `docker compose up` and
// this reference build self-contained without that extra step.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<Northbridge.Shared.Data.NorthbridgeDbContext>();
    db.Database.Migrate();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("SpaOrigins");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();
