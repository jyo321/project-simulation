using Microsoft.EntityFrameworkCore;
using Northbridge.Shared.Entities;

namespace Northbridge.Shared.Data;

public class NorthbridgeDbContext : DbContext
{
    public NorthbridgeDbContext(DbContextOptions<NorthbridgeDbContext> options) : base(options)
    {
    }

    public DbSet<Applicant> Applicants => Set<Applicant>();
    public DbSet<LoanApplication> LoanApplications => Set<LoanApplication>();
    public DbSet<Document> Documents => Set<Document>();
    public DbSet<CreditReport> CreditReports => Set<CreditReport>();
    public DbSet<Decision> Decisions => Set<Decision>();
    public DbSet<JobQueueItem> JobQueueItems => Set<JobQueueItem>();
    public DbSet<NotificationLogEntry> NotificationLogEntries => Set<NotificationLogEntry>();
    public DbSet<ApplicationStatusProjection> ApplicationStatusProjections => Set<ApplicationStatusProjection>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // snake_case table/column names to match idiomatic Postgres conventions.
        foreach (var entity in modelBuilder.Model.GetEntityTypes())
        {
            entity.SetTableName(ToSnakeCase(entity.GetTableName()!));
            foreach (var property in entity.GetProperties())
            {
                property.SetColumnName(ToSnakeCase(property.Name));
            }
        }

        modelBuilder.Entity<Applicant>(b =>
        {
            b.HasIndex(a => a.Email).IsUnique();
        });

        modelBuilder.Entity<LoanApplication>(b =>
        {
            b.HasOne(la => la.Applicant)
                .WithMany(a => a.LoanApplications)
                .HasForeignKey(la => la.ApplicantId)
                .OnDelete(DeleteBehavior.Restrict);

            b.HasOne(la => la.Decision)
                .WithOne(d => d.LoanApplication!)
                .HasForeignKey<Decision>(d => d.LoanApplicationId);

            b.HasOne(la => la.CreditReport)
                .WithOne(c => c.LoanApplication!)
                .HasForeignKey<CreditReport>(c => c.LoanApplicationId);

            b.Property(la => la.RequestedAmount).HasColumnType("numeric(14,2)");
            b.HasIndex(la => la.Status);
        });

        modelBuilder.Entity<Document>(b =>
        {
            b.HasOne(d => d.LoanApplication)
                .WithMany(la => la.Documents)
                .HasForeignKey(d => d.LoanApplicationId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<JobQueueItem>(b =>
        {
            b.HasIndex(j => new { j.JobType, j.Status });
        });

        modelBuilder.Entity<NotificationLogEntry>(b =>
        {
            b.HasIndex(n => n.Status);
        });

        modelBuilder.Entity<ApplicationStatusProjection>(b =>
        {
            b.HasKey(p => p.LoanApplicationId);
        });
    }

    private static string ToSnakeCase(string input)
    {
        var sb = new System.Text.StringBuilder();
        for (var i = 0; i < input.Length; i++)
        {
            var c = input[i];
            if (char.IsUpper(c))
            {
                if (i > 0) sb.Append('_');
                sb.Append(char.ToLowerInvariant(c));
            }
            else
            {
                sb.Append(c);
            }
        }
        return sb.ToString();
    }
}
