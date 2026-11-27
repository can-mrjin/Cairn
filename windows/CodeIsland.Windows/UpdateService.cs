using System.Net.Http;
using System.Reflection;
using System.Text.Json;

namespace CodeIsland.Windows;

public sealed record UpdateCheckResult(
    bool UpdateAvailable,
    string? LatestVersion,
    string? ReleaseUrl,
    string? ErrorMessage = null);

/// <summary>
/// Checks GitHub Releases for newer Cairn for Windows builds with optional Beta channel support.
/// </summary>
public static class UpdateService
{
    public const string Repository = "zepeng-jin/Cairn";

    private static readonly HttpClient Client = CreateClient();

    public static string CurrentVersion
    {
        get
        {
            var info = Assembly.GetExecutingAssembly()
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            if (!string.IsNullOrWhiteSpace(info))
            {
                var plus = info.IndexOf('+');
                return plus > 0 ? info[..plus] : info;
            }
            return Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.2.1";
        }
    }

    public static async Task<UpdateCheckResult> CheckAsync(bool includeBetaUpdates, CancellationToken cancellationToken = default)
    {
        try
        {
            var endpoint = includeBetaUpdates
                ? $"https://api.github.com/repos/{Repository}/releases?per_page=10"
                : $"https://api.github.com/repos/{Repository}/releases/latest";

            using var response = await Client.GetAsync(endpoint, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return new UpdateCheckResult(false, null, null, $"HTTP {(int)response.StatusCode}");
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);

            var candidates = new List<(string Version, string Url)>();
            if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in doc.RootElement.EnumerateArray())
                {
                    CollectCandidate(item, includeBetaUpdates, candidates);
                }
            }
            else if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                CollectCandidate(doc.RootElement, includeBetaUpdates, candidates);
            }

            var current = CurrentVersion;
            string? bestVersion = null;
            string? bestUrl = null;
            foreach (var candidate in candidates)
            {
                if (!IsNewer(candidate.Version, current)) continue;
                if (bestVersion is null || IsNewer(candidate.Version, bestVersion))
                {
                    bestVersion = candidate.Version;
                    bestUrl = candidate.Url;
                }
            }

            return bestVersion is not null
                ? new UpdateCheckResult(true, bestVersion, bestUrl)
                : new UpdateCheckResult(false, current, null);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            return new UpdateCheckResult(false, null, null, ex.Message);
        }
    }

    public static bool IsNewer(string candidate, string current)
    {
        if (!TryParseSemVer(candidate, out var cMajor, out var cMinor, out var cPatch, out var cPre))
            return false;
        if (!TryParseSemVer(current, out var curMajor, out var curMinor, out var curPatch, out var curPre))
            return true;

        if (cMajor != curMajor) return cMajor > curMajor;
        if (cMinor != curMinor) return cMinor > curMinor;
        if (cPatch != curPatch) return cPatch > curPatch;

        var cIsPre = !string.IsNullOrEmpty(cPre);
        var curIsPre = !string.IsNullOrEmpty(curPre);
        if (cIsPre != curIsPre) return !cIsPre;
        if (!cIsPre) return false;
        return ComparePrerelease(cPre, curPre) > 0;
    }

    private static void CollectCandidate(JsonElement release, bool includeBetaUpdates, List<(string Version, string Url)> results)
    {
        if (release.TryGetProperty("draft", out var draft) && draft.ValueKind == JsonValueKind.True) return;
        var isPre = release.TryGetProperty("prerelease", out var pre) && pre.ValueKind == JsonValueKind.True;
        if (!includeBetaUpdates && isPre) return;

        if (!release.TryGetProperty("tag_name", out var tagProp) || tagProp.ValueKind != JsonValueKind.String) return;
        var rawTag = tagProp.GetString()?.Trim().TrimStart('v', 'V');
        if (string.IsNullOrWhiteSpace(rawTag)) return;

        var htmlUrl = release.TryGetProperty("html_url", out var urlProp) && urlProp.ValueKind == JsonValueKind.String
            ? urlProp.GetString() ?? $"https://github.com/{Repository}/releases"
            : $"https://github.com/{Repository}/releases";

        results.Add((rawTag, htmlUrl));
    }

    private static bool TryParseSemVer(string raw, out int major, out int minor, out int patch, out string prerelease)
    {
        major = minor = patch = 0;
        prerelease = string.Empty;
        var cleaned = raw.Trim().TrimStart('v', 'V');
        var plus = cleaned.IndexOf('+');
        if (plus >= 0) cleaned = cleaned[..plus];

        var dash = cleaned.IndexOf('-');
        var core = dash >= 0 ? cleaned[..dash] : cleaned;
        if (dash >= 0) prerelease = cleaned[(dash + 1)..];

        var parts = core.Split('.');
        if (parts.Length == 0 || !int.TryParse(parts[0], out major)) return false;
        if (parts.Length > 1 && !int.TryParse(parts[1], out minor)) return false;
        if (parts.Length > 2 && !int.TryParse(parts[2], out patch)) return false;
        return true;
    }

    private static int ComparePrerelease(string left, string right)
    {
        var lParts = left.Split('.');
        var rParts = right.Split('.');
        var len = Math.Min(lParts.Length, rParts.Length);
        for (var i = 0; i < len; i++)
        {
            var lNumOk = int.TryParse(lParts[i], out var lNum);
            var rNumOk = int.TryParse(rParts[i], out var rNum);
            int cmp;
            if (lNumOk && rNumOk) cmp = lNum.CompareTo(rNum);
            else if (lNumOk != rNumOk) cmp = lNumOk ? -1 : 1;
            else cmp = string.Compare(lParts[i], rParts[i], StringComparison.OrdinalIgnoreCase);
            if (cmp != 0) return cmp;
        }
        return lParts.Length.CompareTo(rParts.Length);
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"Cairn-Windows/{CurrentVersion}");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }
}
