using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Northbridge.Shared.Data;

/// <summary>
/// Used only by `dotnet ef migrations add/update` at design time. Each API/worker supplies
/// its own real connection string at runtime via configuration — this factory exists solely
/// so EF's tooling has something to construct the DbContext with when generating migrations
/// directly against this class library.
/// </summary>
public class NorthbridgeDbContextFactory : IDesignTimeDbContextFactory<NorthbridgeDbContext>
{
    public NorthbridgeDbContext CreateDbContext(string[] args)
    {
        var optionsBuilder = new DbContextOptionsBuilder<NorthbridgeDbContext>();
        optionsBuilder.UseNpgsql("Host=localhost;Port=5432;Database=northbridge;Username=northbridge;Password=northbridge");
        return new NorthbridgeDbContext(optionsBuilder.Options);
    }
}
